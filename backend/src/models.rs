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
}

#[derive(Debug, Serialize)]
pub struct ImageUploadOut {
    pub url: String,
}

fn default_kind() -> String {
    "lab".to_string()
}
fn default_one() -> i64 {
    1
}
fn default_true() -> bool {
    true
}
