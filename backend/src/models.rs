use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
pub struct Resource {
    pub id: i64,
    pub name: String,
    pub kind: String,
    pub description: String,
    pub image_url: String,
    pub total_quantity: i64,
    pub individual_bookable: bool,
    pub sort_order: i64,
    pub is_active: bool,
    /// 默认负责人（开门人）用户名；为空表示未指定。
    pub manager: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Slot {
    pub id: i64,
    pub name: String,
    pub start_time: String,
    pub end_time: String,
    pub sort_order: i64,
    pub is_active: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct Booking {
    pub id: i64,
    pub resource_id: i64,
    pub slot_id: i64,
    pub date: String,
    pub applicant_name: String,
    pub phone: String,
    pub major: String,
    pub num_people: i64,
    pub instructor: String,
    pub description: String,
    pub quantity: i64,
    pub status: String,
    pub created_at: String,
    pub verified_at: Option<String>,
    pub admin_note: String,
    pub processed_by: String,
    pub resource: Resource,
    pub slot: Slot,
}

// ---------- Availability ----------
#[derive(Debug, Serialize)]
pub struct SlotAvailability {
    pub slot: Slot,
    pub total_quantity: i64,
    pub booked_quantity: i64,
    pub available: i64,
}

#[derive(Debug, Serialize)]
pub struct ResourceAvailability {
    pub resource: Resource,
    pub date: String,
    pub slots: Vec<SlotAvailability>,
}

// ---------- Request payloads ----------
#[derive(Debug, Deserialize)]
pub struct ResourceCreate {
    pub name: String,
    #[serde(default = "default_kind")]
    pub kind: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub image_url: String,
    #[serde(default = "default_one")]
    pub total_quantity: i64,
    #[serde(default = "default_true")]
    pub individual_bookable: bool,
    #[serde(default)]
    pub sort_order: i64,
    #[serde(default = "default_true")]
    pub is_active: bool,
    #[serde(default)]
    pub manager: String,
}

#[derive(Debug, Deserialize)]
pub struct ResourceUpdate {
    pub name: Option<String>,
    pub kind: Option<String>,
    pub description: Option<String>,
    pub image_url: Option<String>,
    pub total_quantity: Option<i64>,
    pub individual_bookable: Option<bool>,
    pub sort_order: Option<i64>,
    pub is_active: Option<bool>,
    pub manager: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SlotCreate {
    pub name: String,
    pub start_time: String,
    pub end_time: String,
    #[serde(default)]
    pub sort_order: i64,
    #[serde(default = "default_true")]
    pub is_active: bool,
}

#[derive(Debug, Deserialize)]
pub struct SlotUpdate {
    pub name: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub sort_order: Option<i64>,
    pub is_active: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct BookingCreate {
    pub resource_id: i64,
    pub slot_id: i64,
    pub date: String,
    pub applicant_name: String,
    pub phone: String,
    #[serde(default)]
    pub major: String,
    #[serde(default = "default_one")]
    pub num_people: i64,
    #[serde(default)]
    pub instructor: String,
    #[serde(default)]
    pub description: String,
    #[serde(default = "default_one")]
    pub quantity: i64,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct TokenOut {
    pub token: String,
    pub username: String,
    pub role: String,
}

#[derive(Debug, Serialize)]
pub struct ImageUploadOut {
    pub url: String,
}

// ---------- Booking actions (批量) ----------
#[derive(Debug, Deserialize)]
pub struct BatchAction {
    pub ids: Vec<i64>,
    #[serde(default)]
    pub note: String,
}

// ---------- Admin accounts（多管理员） ----------
#[derive(Debug, Clone, Serialize)]
pub struct Admin {
    pub id: i64,
    pub username: String,
    pub role: String,
    pub is_active: bool,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
pub struct AdminCreate {
    pub username: String,
    pub password: String,
    #[serde(default = "default_role")]
    pub role: String,
}

#[derive(Debug, Deserialize)]
pub struct AdminUpdate {
    pub password: Option<String>,
    pub role: Option<String>,
    pub is_active: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct MeOut {
    pub username: String,
    pub role: String,
}

// ---------- Duty shifts（排班 / 开门负责人） ----------
#[derive(Debug, Clone, Serialize)]
pub struct DutyShift {
    pub id: i64,
    /// 0=周日..6=周六；-1 表示每天。
    pub weekday: i64,
    /// 时段 id；0 表示全部时段。
    pub slot_id: i64,
    /// 资源 id；0 表示全部资源。
    pub resource_id: i64,
    pub admin_username: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
pub struct DutyShiftCreate {
    #[serde(default = "default_neg_one")]
    pub weekday: i64,
    #[serde(default)]
    pub slot_id: i64,
    #[serde(default)]
    pub resource_id: i64,
    pub admin_username: String,
}

// ---------- Operation log（操作日志） ----------
#[derive(Debug, Clone, Serialize)]
pub struct OperationLog {
    pub id: i64,
    pub actor: String,
    pub action: String,
    pub target: String,
    pub detail: String,
    pub created_at: String,
}

// ---------- Stats report（统计报表） ----------
#[derive(Debug, Serialize)]
pub struct LabeledCount {
    pub label: String,
    pub value: i64,
}

#[derive(Debug, Serialize)]
pub struct StatsReport {
    pub total: i64,
    pub booked: i64,
    pub verified: i64,
    pub cancelled: i64,
    pub today: i64,
    pub this_week: i64,
    pub this_month: i64,
    pub trend: Vec<LabeledCount>,
    pub by_resource: Vec<LabeledCount>,
    pub by_slot: Vec<LabeledCount>,
}

fn default_kind() -> String {
    "lab".to_string()
}
fn default_role() -> String {
    "staff".to_string()
}
fn default_neg_one() -> i64 {
    -1
}
fn default_one() -> i64 {
    1
}
fn default_true() -> bool {
    true
}
