use std::collections::HashMap;
use std::fs;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::{
    body::Body,
    extract::{Multipart, Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use rusqlite::Connection;
use serde_json::json;

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
}

impl AppState {
    fn conn(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.db.lock().expect("db mutex poisoned")
    }

    fn require_admin(&self, headers: &HeaderMap) -> ApiResult<String> {
        let token = headers
            .get(header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(|| ApiError::unauthorized("未登录"))?;
        auth::verify_token(&self.config.secret_key, token, self.config.token_max_age)
            .map_err(ApiError::unauthorized)
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
    if payload.username != st.config.admin_username || payload.password != st.config.admin_password
    {
        return Err(ApiError::unauthorized("用户名或密码错误"));
    }
    let token = auth::create_token(&st.config.secret_key, &payload.username);
    Ok(Json(TokenOut {
        token,
        username: payload.username,
    }))
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
    st.require_admin(&headers)?;
    let resource = db::create_resource(&st.conn(), &payload)?;
    Ok((StatusCode::CREATED, Json(resource)).into_response())
}

pub async fn update_resource(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<ResourceUpdate>,
) -> ApiResult<Json<Resource>> {
    st.require_admin(&headers)?;
    let conn = st.conn();
    let current = db::get_resource(&conn, id)?.ok_or_else(|| ApiError::not_found("资源不存在"))?;
    Ok(Json(db::update_resource(&conn, &current, &payload)?))
}

pub async fn delete_resource(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<StatusCode> {
    st.require_admin(&headers)?;
    let conn = st.conn();
    db::get_resource(&conn, id)?.ok_or_else(|| ApiError::not_found("资源不存在"))?;
    db::delete_resource(&conn, id)?;
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
    st.require_admin(&headers)?;
    let slot = db::create_slot(&st.conn(), &payload)?;
    Ok((StatusCode::CREATED, Json(slot)).into_response())
}

pub async fn update_slot(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(payload): Json<SlotUpdate>,
) -> ApiResult<Json<Slot>> {
    st.require_admin(&headers)?;
    let conn = st.conn();
    let current = db::get_slot(&conn, id)?.ok_or_else(|| ApiError::not_found("时间段不存在"))?;
    Ok(Json(db::update_slot(&conn, &current, &payload)?))
}

pub async fn delete_slot(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<StatusCode> {
    st.require_admin(&headers)?;
    let conn = st.conn();
    db::get_slot(&conn, id)?.ok_or_else(|| ApiError::not_found("时间段不存在"))?;
    db::delete_slot(&conn, id)?;
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
) -> ApiResult<Json<Booking>> {
    st.require_admin(&headers)?;
    let conn = st.conn();
    let booking = db::get_booking(&conn, id)?.ok_or_else(|| ApiError::not_found("预约不存在"))?;
    match booking.status.as_str() {
        "cancelled" => return Err(ApiError::bad_request("已取消的预约不可通过")),
        "verified" => return Err(ApiError::bad_request("该预约已通过")),
        _ => {}
    }
    Ok(Json(db::set_booking_status(
        &conn,
        id,
        "verified",
        Some(db::now_iso()),
    )?))
}

pub async fn cancel_booking(
    State(st): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<i64>,
) -> ApiResult<Json<Booking>> {
    st.require_admin(&headers)?;
    let conn = st.conn();
    let booking = db::get_booking(&conn, id)?.ok_or_else(|| ApiError::not_found("预约不存在"))?;
    Ok(Json(db::set_booking_status(
        &conn,
        id,
        "cancelled",
        booking.verified_at,
    )?))
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
