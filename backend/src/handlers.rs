use std::collections::HashMap;
use std::fs;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use axum::{
    body::Body,
    extract::{Multipart, Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse, Response,
    },
    Json,
};
use rusqlite::Connection;
use serde_json::json;
use tokio::sync::broadcast;
use tokio_stream::{wrappers::BroadcastStream, StreamExt};

use crate::config::Config;
use crate::db::{self, BookingFilter};
use crate::error::{ApiError, ApiResult};
use crate::models::*;
use crate::{auth, excel};

const MAX_IMAGE_UPLOAD_BYTES: usize = 5 * 1024 * 1024;

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<Mutex<Connection>>,
    pub config: Arc<Config>,
    /// 实时事件广播（SSE 推送）。
    pub events: broadcast::Sender<String>,
    /// 唤醒「开门提醒」调度器重新计算下一个提醒时刻（新预约入库时触发）。
    pub reminder_wake: Arc<tokio::sync::Notify>,
}

impl AppState {
    pub(crate) fn conn(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.db.lock().expect("db mutex poisoned")
    }

    fn verify_bearer(&self, token: &str) -> ApiResult<String> {
        auth::verify_token(&self.config.secret_key, token, self.config.token_max_age)
            .map_err(ApiError::unauthorized)
    }

    /// 校验登录并返回用户名。
    fn require_admin(&self, headers: &HeaderMap) -> ApiResult<String> {
        let token = headers
            .get(header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(|| ApiError::unauthorized("未登录"))?;
        self.verify_bearer(token)
    }

    /// 校验登录并返回 (用户名, 角色)。
    fn require_admin_full(&self, headers: &HeaderMap) -> ApiResult<(String, String)> {
        let username = self.require_admin(headers)?;
        let role = self.role_for(&username);
        Ok((username, role))
    }

    /// 仅超级管理员可访问。
    fn require_super(&self, headers: &HeaderMap) -> ApiResult<String> {
        let (username, role) = self.require_admin_full(headers)?;
        if role != "super" {
            return Err(ApiError::new(StatusCode::FORBIDDEN, "仅超级管理员可执行此操作"));
        }
        Ok(username)
    }

    /// 解析某用户名的角色：配置文件里的内置管理员恒为 super，其余查 admins 表。
    fn role_for(&self, username: &str) -> String {
        if username == self.config.admin_username {
            return "super".to_string();
        }
        db::get_admin_by_username(&self.conn(), username)
            .ok()
            .flatten()
            .map(|a| a.role)
            .unwrap_or_else(|| "staff".to_string())
    }

    /// 向所有 SSE 订阅者推送一条事件（附带当前待处理数量）。
    fn publish(&self, event_type: &str) {
        let pending = db::stats(&self.conn()).map(|s| s.booked).unwrap_or(0);
        let payload = json!({
            "type": event_type,
            "pending": pending,
            "ts": db::now_iso(),
        })
        .to_string();
        let _ = self.events.send(payload);
    }

    fn log(&self, actor: &str, action: &str, target: &str, detail: &str) {
        let _ = db::add_log(&self.conn(), actor, action, target, detail);
    }

    /// 唤醒开门提醒调度器（有新预约、可能存在更早的提醒时刻时调用）。
    pub(crate) fn wake_reminder(&self) {
        self.reminder_wake.notify_one();
    }
}

pub async fn healthz() -> Json<serde_json::Value> {
    Json(json!({ "status": "ok" }))
}

// ---------- Public ----------
pub async fn list_resources(State(st): State<AppState>) -> ApiResult<Json<Vec<Resource>>> {
    Ok(Json(db::list_resources(&st.conn(), true)?))
}

pub async fn list_slots(State(st): State<AppState>) -> ApiResult<Json<Vec<Slot>>> {
    Ok(Json(db::list_slots(&st.conn(), true)?))
}

pub async fn availability(
    State(st): State<AppState>,
    Path(resource_id): Path<i64>,
    Query(q): Query<HashMap<String, String>>,
) -> ApiResult<Json<ResourceAvailability>> {
    let date = q
        .get("date")
        .cloned()
        .ok_or_else(|| ApiError::bad_request("缺少 date 参数"))?;
    let conn = st.conn();
    let resource = db::get_resource(&conn, resource_id)?
        .filter(|r| r.is_active)
        .ok_or_else(|| ApiError::not_found("资源不存在"))?;
    let slots = db::list_slots(&conn, true)?;
    let mut out = Vec::with_capacity(slots.len());
    for slot in slots {
        let used = db::booked_quantity(&conn, resource_id, slot.id, &date)?;
        out.push(SlotAvailability {
            total_quantity: resource.total_quantity,
            booked_quantity: used,
            available: (resource.total_quantity - used).max(0),
            slot,
        });
    }
    Ok(Json(ResourceAvailability {
        resource,
        date,
        slots: out,
    }))
}

pub async fn create_booking(
    State(st): State<AppState>,
    Json(payload): Json<BookingCreate>,
) -> ApiResult<Response> {
    if payload.applicant_name.trim().is_empty()
        || payload.phone.trim().is_empty()
        || payload.major.trim().is_empty()
        || payload.instructor.trim().is_empty()
        || payload.description.trim().is_empty()
    {
        return Err(ApiError::bad_request("请填写完整的预约信息（所有字段均为必填）"));
    }
    let conn = st.conn();
    let resource = db::get_resource(&conn, payload.resource_id)?
        .filter(|r| r.is_active)
        .ok_or_else(|| ApiError::not_found("资源不存在"))?;
    if !resource.individual_bookable {
        return Err(ApiError::bad_request(
            "该资源学生个人不可预约，请联系指导老师统一安排。",
        ));
    }
    let slot = db::get_slot(&conn, payload.slot_id)?
        .filter(|s| s.is_active)
        .ok_or_else(|| ApiError::not_found("时间段不存在"))?;
    if payload.quantity < 1 {
        return Err(ApiError::bad_request("预约数量至少为 1"));
    }

    let used = db::booked_quantity(&conn, resource.id, slot.id, &payload.date)?;
    if used + payload.quantity > resource.total_quantity {
        let remaining = (resource.total_quantity - used).max(0);
        return Err(ApiError::conflict(format!(
            "该时段名额不足，仅剩 {remaining} 个可预约。"
        )));
    }

    let booking = db::create_booking(&conn, &payload)?;
    drop(conn);
    // 新预约入库后立即推送给所有在线管理端（SSE），并唤醒开门提醒调度器。
    st.publish("new_booking");
    st.wake_reminder();
    let mut resp = (StatusCode::CREATED, Json(booking)).into_response();
    resp.headers_mut()
        .insert(header::SET_COOKIE, remember_phone_cookie(payload.phone.trim()));
    Ok(resp)
}

// ---------- Admin: auth ----------
pub async fn login(
    State(st): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> ApiResult<Json<TokenOut>> {
    // 1) 内置配置管理员（恒为超级管理员）。
    let is_config_admin =
        payload.username == st.config.admin_username && payload.password == st.config.admin_password;
    // 2) admins 表里的其他管理员（密码经 HMAC 派生存储）。
    let table_ok = if is_config_admin {
        false
    } else {
        match db::admin_password_hash(&st.conn(), &payload.username)? {
            Some(hash) => auth::verify_password(&st.config.secret_key, &payload.password, &hash),
            None => false,
        }
    };
    if !is_config_admin && !table_ok {
        return Err(ApiError::unauthorized("用户名或密码错误"));
    }
    let role = st.role_for(&payload.username);
    let token = auth::create_token(&st.config.secret_key, &payload.username);
    Ok(Json(TokenOut {
        token,
        username: payload.username,
        role,
    }))
}

pub async fn me(State(st): State<AppState>, headers: HeaderMap) -> ApiResult<Json<MeOut>> {
    let (username, role) = st.require_admin_full(&headers)?;
    Ok(Json(MeOut { username, role }))
}

// ---------- Admin: resources ----------
pub async fn admin_list_resources(
    State(st): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Vec<Resource>>> {
    st.require_admin(&headers)?;
    Ok(Json(db::list_resources(&st.conn(), false)?))
}

pub async fn create_resource(
    State(st): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<ResourceCreate>,
) -> ApiResult<Response> {
    let actor = st.require_admin(&headers)?;
    let resource = db::create_resource(&st.conn(), &payload)?;
    st.log(&actor, "resource.create", &format!("resource:{}", resource.id), &resource.name);
    Ok((StatusCode::CREATED, Json(resource)).into_response())
}

pub async fn update_resource(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<ResourceUpdate>,
) -> ApiResult<Json<Resource>> {
    let actor = st.require_admin(&headers)?;
    let updated = {
        let conn = st.conn();
        let current = db::get_resource(&conn, id)?.ok_or_else(|| ApiError::not_found("资源不存在"))?;
        db::update_resource(&conn, &current, &payload)?
    };
    st.log(&actor, "resource.update", &format!("resource:{id}"), &updated.name);
    Ok(Json(updated))
}

pub async fn delete_resource(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<StatusCode> {
    let actor = st.require_admin(&headers)?;
    let name = {
        let conn = st.conn();
        let r = db::get_resource(&conn, id)?.ok_or_else(|| ApiError::not_found("资源不存在"))?;
        db::delete_resource(&conn, id)?;
        r.name
    };
    st.log(&actor, "resource.delete", &format!("resource:{id}"), &name);
    Ok(StatusCode::NO_CONTENT)
}

pub async fn upload_image(
    State(st): State<AppState>,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> ApiResult<Json<ImageUploadOut>> {
    st.require_admin(&headers)?;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| ApiError::bad_request("无法读取上传文件"))?
    {
        if field.name() != Some("image") {
            continue;
        }

        let content_type = field.content_type().map(str::to_string);
        let file_name = field.file_name().map(str::to_string);
        let ext = image_extension(content_type.as_deref(), file_name.as_deref())
            .ok_or_else(|| ApiError::bad_request("仅支持 PNG、JPG、WebP 或 GIF 图片"))?;
        let bytes = field
            .bytes()
            .await
            .map_err(|_| ApiError::bad_request("无法读取上传文件"))?;
        if bytes.is_empty() {
            return Err(ApiError::bad_request("图片文件不能为空"));
        }
        if bytes.len() > MAX_IMAGE_UPLOAD_BYTES {
            return Err(ApiError::new(
                StatusCode::PAYLOAD_TOO_LARGE,
                "图片不能超过 5MB",
            ));
        }
        if !image_bytes_match(ext, &bytes) {
            return Err(ApiError::bad_request("图片内容与文件格式不匹配"));
        }

        let upload_dir = st.config.data_dir.join("uploads").join("images");
        fs::create_dir_all(&upload_dir).map_err(|e| {
            ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("创建上传目录失败：{e}"),
            )
        })?;
        let filename = format!("resource-{}.{}", upload_stamp(), ext);
        fs::write(upload_dir.join(&filename), &bytes).map_err(|e| {
            ApiError::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("保存图片失败：{e}"),
            )
        })?;

        return Ok(Json(ImageUploadOut {
            url: format!("/uploads/images/{filename}"),
        }));
    }

    Err(ApiError::bad_request("请选择要上传的图片"))
}

pub async fn uploaded_image(
    State(st): State<AppState>,
    Path(filename): Path<String>,
) -> ApiResult<Response> {
    if !safe_filename(&filename) {
        return Err(ApiError::not_found("图片不存在"));
    }
    let path = st
        .config
        .data_dir
        .join("uploads")
        .join("images")
        .join(&filename);
    let body = fs::read(&path).map_err(|_| ApiError::not_found("图片不存在"))?;
    let mime = mime_guess::from_path(&path).first_or_octet_stream();
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, mime.as_ref())
        .body(Body::from(body))
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
}

fn image_extension(content_type: Option<&str>, file_name: Option<&str>) -> Option<&'static str> {
    let from_name = file_name
        .and_then(|name| {
            name.rsplit_once('.')
                .map(|(_, ext)| ext.to_ascii_lowercase())
        })
        .and_then(|ext| match ext.as_str() {
            "jpg" | "jpeg" => Some("jpg"),
            "png" => Some("png"),
            "webp" => Some("webp"),
            "gif" => Some("gif"),
            _ => None,
        });
    if from_name.is_some() {
        return from_name;
    }
    match content_type {
        Some("image/jpeg") => Some("jpg"),
        Some("image/png") => Some("png"),
        Some("image/webp") => Some("webp"),
        Some("image/gif") => Some("gif"),
        _ => None,
    }
}

fn upload_stamp() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default()
}

fn image_bytes_match(ext: &str, bytes: &[u8]) -> bool {
    match ext {
        "jpg" => bytes.starts_with(&[0xff, 0xd8, 0xff]),
        "png" => bytes.starts_with(b"\x89PNG\r\n\x1a\n"),
        "gif" => bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a"),
        "webp" => bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP",
        _ => false,
    }
}

fn safe_filename(filename: &str) -> bool {
    !filename.is_empty()
        && !filename.contains("..")
        && filename
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '-' | '_'))
}

// ---------- Admin: slots ----------
pub async fn admin_list_slots(
    State(st): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Vec<Slot>>> {
    st.require_admin(&headers)?;
    Ok(Json(db::list_slots(&st.conn(), false)?))
}

pub async fn create_slot(
    State(st): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<SlotCreate>,
) -> ApiResult<Response> {
    let actor = st.require_admin(&headers)?;
    let slot = db::create_slot(&st.conn(), &payload)?;
    st.log(&actor, "slot.create", &format!("slot:{}", slot.id), &slot.name);
    Ok((StatusCode::CREATED, Json(slot)).into_response())
}

pub async fn update_slot(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<SlotUpdate>,
) -> ApiResult<Json<Slot>> {
    let actor = st.require_admin(&headers)?;
    let updated = {
        let conn = st.conn();
        let current = db::get_slot(&conn, id)?.ok_or_else(|| ApiError::not_found("时间段不存在"))?;
        db::update_slot(&conn, &current, &payload)?
    };
    st.log(&actor, "slot.update", &format!("slot:{id}"), &updated.name);
    Ok(Json(updated))
}

pub async fn delete_slot(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<StatusCode> {
    let actor = st.require_admin(&headers)?;
    let name = {
        let conn = st.conn();
        let s = db::get_slot(&conn, id)?.ok_or_else(|| ApiError::not_found("时间段不存在"))?;
        db::delete_slot(&conn, id)?;
        s.name
    };
    st.log(&actor, "slot.delete", &format!("slot:{id}"), &name);
    Ok(StatusCode::NO_CONTENT)
}

// ---------- Admin: bookings ----------
fn filter_from_query(q: &HashMap<String, String>) -> BookingFilter {
    let pick = |k: &str| q.get(k).filter(|v| !v.is_empty()).cloned();
    BookingFilter {
        status: pick("status"),
        resource_id: pick("resource_id").and_then(|v| v.parse().ok()),
        date: pick("date"),
        keyword: pick("keyword"),
        phone: None,
    }
}

const PHONE_COOKIE: &str = "mine_phone";

/// 从 Cookie 头里取出记住的预约手机号（创建预约时写入）。
fn phone_from_cookie(headers: &HeaderMap) -> Option<String> {
    let cookies = headers.get(header::COOKIE)?.to_str().ok()?;
    cookies.split(';').find_map(|kv| {
        let (k, v) = kv.split_once('=')?;
        if k.trim() == PHONE_COOKIE {
            let v = v.trim();
            if v.is_empty() {
                None
            } else {
                Some(v.to_string())
            }
        } else {
            None
        }
    })
}

/// 公开接口：按手机号查询“我的预约”。手机号来自查询参数，缺省则读 Cookie。
/// 命中后顺带把手机号写入长期 Cookie，方便下次自动带出。
pub async fn my_bookings(
    State(st): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<HashMap<String, String>>,
) -> ApiResult<Response> {
    let phone = q
        .get("phone")
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .or_else(|| phone_from_cookie(&headers));

    let phone = match phone {
        Some(p) => p,
        None => return Err(ApiError::bad_request("请输入手机号查询")),
    };

    let filter = BookingFilter {
        phone: Some(phone.clone()),
        ..Default::default()
    };
    let bookings = db::list_bookings(&st.conn(), &filter)?;

    let mut resp = Json(bookings).into_response();
    resp.headers_mut()
        .insert(header::SET_COOKIE, remember_phone_cookie(&phone));
    Ok(resp)
}

/// 一年有效期的手机号 Cookie；同源 SameSite=Lax，JS 可读以便前端展示。
fn remember_phone_cookie(phone: &str) -> axum::http::HeaderValue {
    let value = format!("{PHONE_COOKIE}={phone}; Path=/; Max-Age=31536000; SameSite=Lax");
    axum::http::HeaderValue::from_str(&value)
        .unwrap_or_else(|_| axum::http::HeaderValue::from_static(""))
}

pub async fn admin_list_bookings(
    State(st): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<HashMap<String, String>>,
) -> ApiResult<Json<Vec<Booking>>> {
    st.require_admin(&headers)?;
    let filter = filter_from_query(&q);
    Ok(Json(db::list_bookings(&st.conn(), &filter)?))
}

pub async fn verify_booking(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Query(q): Query<HashMap<String, String>>,
) -> ApiResult<Json<Booking>> {
    let actor = st.require_admin(&headers)?;
    let note = q.get("note").cloned().unwrap_or_default();
    let updated = {
        let conn = st.conn();
        let booking =
            db::get_booking(&conn, id)?.ok_or_else(|| ApiError::not_found("预约不存在"))?;
        match booking.status.as_str() {
            "cancelled" => return Err(ApiError::bad_request("已取消的预约不可通过")),
            "verified" => return Err(ApiError::bad_request("该预约已通过")),
            _ => {}
        }
        db::set_booking_status(&conn, id, "verified", Some(db::now_iso()), &note, &actor)?
    };
    st.log(&actor, "booking.verify", &format!("booking:{id}"), &note);
    st.publish("update");
    Ok(Json(updated))
}

pub async fn cancel_booking(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Query(q): Query<HashMap<String, String>>,
) -> ApiResult<Json<Booking>> {
    let actor = st.require_admin(&headers)?;
    let note = q.get("note").cloned().unwrap_or_default();
    let updated = {
        let conn = st.conn();
        let booking =
            db::get_booking(&conn, id)?.ok_or_else(|| ApiError::not_found("预约不存在"))?;
        db::set_booking_status(&conn, id, "cancelled", booking.verified_at, &note, &actor)?
    };
    st.log(&actor, "booking.cancel", &format!("booking:{id}"), &note);
    st.publish("update");
    Ok(Json(updated))
}

/// 彻底删除预约记录（不可恢复，区别于「取消」）。
pub async fn delete_booking(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<StatusCode> {
    let actor = st.require_admin(&headers)?;
    let summary = {
        let conn = st.conn();
        let booking =
            db::get_booking(&conn, id)?.ok_or_else(|| ApiError::not_found("预约不存在"))?;
        db::delete_booking(&conn, id)?;
        format!(
            "{} · {} · {} {}",
            booking.applicant_name, booking.resource.name, booking.date, booking.slot.name
        )
    };
    st.log(&actor, "booking.delete", &format!("booking:{id}"), &summary);
    st.publish("update");
    Ok(StatusCode::NO_CONTENT)
}

/// 批量审批 / 取消。返回成功处理的数量，逐条跳过非法状态。
pub async fn batch_bookings(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(op): Path<String>,
    Json(payload): Json<BatchAction>,
) -> ApiResult<Json<serde_json::Value>> {
    let actor = st.require_admin(&headers)?;
    if op == "delete" {
        let mut deleted = 0i64;
        {
            let conn = st.conn();
            for id in &payload.ids {
                if db::get_booking(&conn, *id)?.is_none() {
                    continue;
                }
                db::delete_booking(&conn, *id)?;
                deleted += 1;
            }
        }
        st.log(
            &actor,
            "booking.batch_delete",
            &format!("count:{deleted}"),
            &payload.note,
        );
        st.publish("update");
        return Ok(Json(json!({ "processed": deleted })));
    }
    let target_status = match op.as_str() {
        "verify" => "verified",
        "cancel" => "cancelled",
        _ => return Err(ApiError::bad_request("不支持的批量操作")),
    };
    let mut done = 0i64;
    {
        let conn = st.conn();
        for id in &payload.ids {
            let Some(booking) = db::get_booking(&conn, *id)? else {
                continue;
            };
            if target_status == "verified" && booking.status != "booked" {
                continue;
            }
            if target_status == "cancelled" && booking.status == "cancelled" {
                continue;
            }
            let verified_at = if target_status == "verified" {
                Some(db::now_iso())
            } else {
                booking.verified_at.clone()
            };
            db::set_booking_status(&conn, *id, target_status, verified_at, &payload.note, &actor)?;
            done += 1;
        }
    }
    st.log(
        &actor,
        &format!("booking.batch_{op}"),
        &format!("count:{done}"),
        &payload.note,
    );
    st.publish("update");
    Ok(Json(json!({ "processed": done })))
}

pub async fn stats(
    State(st): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<serde_json::Value>> {
    st.require_admin(&headers)?;
    let s = db::stats(&st.conn())?;
    Ok(Json(json!({
        "total": s.total,
        "booked": s.booked,
        "verified": s.verified,
        "cancelled": s.cancelled,
        "today": s.today,
    })))
}

pub async fn stats_report(
    State(st): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<StatsReport>> {
    st.require_admin(&headers)?;
    Ok(Json(db::stats_report(&st.conn())?))
}

// ---------- Admin: operation logs ----------
pub async fn list_logs(
    State(st): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<HashMap<String, String>>,
) -> ApiResult<Json<Vec<OperationLog>>> {
    st.require_admin(&headers)?;
    let limit = q
        .get("limit")
        .and_then(|v| v.parse::<i64>().ok())
        .unwrap_or(200)
        .clamp(1, 1000);
    Ok(Json(db::list_logs(&st.conn(), limit)?))
}

// ---------- Admin: 多管理员账号 ----------
pub async fn list_admins(
    State(st): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Vec<Admin>>> {
    st.require_super(&headers)?;
    Ok(Json(db::list_admins(&st.conn())?))
}

pub async fn create_admin(
    State(st): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<AdminCreate>,
) -> ApiResult<Response> {
    let actor = st.require_super(&headers)?;
    let username = payload.username.trim().to_string();
    if username.is_empty() || payload.password.len() < 4 {
        return Err(ApiError::bad_request("用户名不能为空，密码至少 4 位"));
    }
    if username == st.config.admin_username {
        return Err(ApiError::conflict("该用户名为内置管理员，不能重复创建"));
    }
    let role = if payload.role == "super" { "super" } else { "staff" };
    let hash = auth::hash_password(&st.config.secret_key, &payload.password);
    let admin = {
        let conn = st.conn();
        if db::get_admin_by_username(&conn, &username)?.is_some() {
            return Err(ApiError::conflict("该用户名已存在"));
        }
        db::create_admin(&conn, &username, &hash, role)?
    };
    st.log(&actor, "admin.create", &format!("admin:{}", admin.id), &username);
    Ok((StatusCode::CREATED, Json(admin)).into_response())
}

pub async fn update_admin(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<AdminUpdate>,
) -> ApiResult<Json<Admin>> {
    let actor = st.require_super(&headers)?;
    let new_hash = payload
        .password
        .as_ref()
        .filter(|p| !p.is_empty())
        .map(|p| auth::hash_password(&st.config.secret_key, p));
    let role = payload
        .role
        .as_deref()
        .map(|r| if r == "super" { "super" } else { "staff" });
    let updated = {
        let conn = st.conn();
        // 防止把最后一个超级管理员降级 / 停用，导致无人可管理。
        if let Some(existing) = db::list_admins(&conn)?.into_iter().find(|a| a.id == id) {
            let demoting = role == Some("staff") || payload.is_active == Some(false);
            if existing.role == "super" && demoting && db::count_super_admins(&conn)? <= 1 {
                return Err(ApiError::bad_request("至少需要保留一个启用的超级管理员"));
            }
        }
        db::update_admin(
            &conn,
            id,
            new_hash.as_deref(),
            role,
            payload.is_active,
        )?
        .ok_or_else(|| ApiError::not_found("管理员不存在"))?
    };
    st.log(&actor, "admin.update", &format!("admin:{id}"), &updated.username);
    Ok(Json(updated))
}

pub async fn delete_admin(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<StatusCode> {
    let actor = st.require_super(&headers)?;
    {
        let conn = st.conn();
        if let Some(existing) = db::list_admins(&conn)?.into_iter().find(|a| a.id == id) {
            if existing.role == "super" && db::count_super_admins(&conn)? <= 1 {
                return Err(ApiError::bad_request("至少需要保留一个启用的超级管理员"));
            }
        }
        db::delete_admin(&conn, id)?;
    }
    st.log(&actor, "admin.delete", &format!("admin:{id}"), "");
    Ok(StatusCode::NO_CONTENT)
}

// ---------- Admin: 排班（开门负责人） ----------
pub async fn list_shifts(
    State(st): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Vec<DutyShift>>> {
    st.require_admin(&headers)?;
    Ok(Json(db::list_shifts(&st.conn())?))
}

pub async fn create_shift(
    State(st): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<DutyShiftCreate>,
) -> ApiResult<Response> {
    let actor = st.require_super(&headers)?;
    let admin_username = payload.admin_username.trim().to_string();
    if admin_username.is_empty() {
        return Err(ApiError::bad_request("请指定负责人"));
    }
    if !(-1..=6).contains(&payload.weekday) {
        return Err(ApiError::bad_request("星期取值应为 -1(每天) 或 0~6"));
    }
    let shift = db::create_shift(
        &st.conn(),
        payload.weekday,
        payload.slot_id,
        payload.resource_id,
        &admin_username,
    )?;
    st.log(
        &actor,
        "shift.create",
        &format!("shift:{}", shift.id),
        &admin_username,
    );
    Ok((StatusCode::CREATED, Json(shift)).into_response())
}

pub async fn delete_shift(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<StatusCode> {
    let actor = st.require_super(&headers)?;
    db::delete_shift(&st.conn(), id)?;
    st.log(&actor, "shift.delete", &format!("shift:{id}"), "");
    Ok(StatusCode::NO_CONTENT)
}

// ---------- Admin: 实时推送（SSE） ----------
pub async fn admin_events(
    State(st): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<HashMap<String, String>>,
) -> Response {
    // EventSource 无法自定义请求头，这里同时支持 Authorization 头与 ?token= 查询参数。
    let auth_ok = st.require_admin(&headers).is_ok()
        || q
            .get("token")
            .map(|t| st.verify_bearer(t).is_ok())
            .unwrap_or(false);
    if !auth_ok {
        return ApiError::unauthorized("未登录").into_response();
    }
    let rx = st.events.subscribe();
    let stream = BroadcastStream::new(rx).map(|msg| {
        let data = msg.unwrap_or_else(|_| "{\"type\":\"lagged\"}".to_string());
        Ok::<_, std::convert::Infallible>(Event::default().data(data))
    });
    Sse::new(stream)
        .keep_alive(
            KeepAlive::new()
                .interval(Duration::from_secs(20))
                .text("ping"),
        )
        .into_response()
}

pub async fn export_bookings(
    State(st): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<HashMap<String, String>>,
) -> ApiResult<Response> {
    st.require_admin(&headers)?;
    let filter = filter_from_query(&q);
    let bookings = db::list_bookings(&st.conn(), &filter)?;
    let content = excel::bookings_to_xlsx(&bookings)
        .map_err(|e| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, format!("导出失败：{e}")))?;
    let filename = format!(
        "bookings_{}.xlsx",
        chrono::Utc::now().format("%Y%m%d_%H%M%S")
    );
    Ok((
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".to_string(),
            ),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename={filename}"),
            ),
        ],
        content,
    )
        .into_response())
}
