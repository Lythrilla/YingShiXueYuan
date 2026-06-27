use rusqlite::{params, Connection};

use crate::db::now_iso;

const DEFAULT_SLOTS: &[(&str, &str, &str, i64)] = &[
    ("上午", "08:00", "12:00", 1),
    ("下午", "12:00", "18:00", 2),
    ("晚上", "18:00", "23:00", 3),
];

// (name, kind, description, total_quantity, individual_bookable, sort_order)
const DEFAULT_RESOURCES: &[(&str, &str, &str, i64, bool, i64)] = &[
    (
        "全景声棚",
        "lab",
        "沉浸式全景声录音棚。学生个人不可预约，需在指导老师带领下使用；面向外部录音借用开放。",
        1,
        false,
        1,
    ),
    (
        "5.1 编辑室",
        "lab",
        "5.1 声道音频编辑制作工作室。",
        1,
        true,
        2,
    ),
    (
        "拟音棚",
        "lab",
        "用于拟音（Foley）录制的专业棚。",
        1,
        true,
        3,
    ),
    ("5.1 终混棚", "lab", "5.1 环绕声终混录音棚。", 1, true, 4),
    (
        "同期拾音设备基础套装",
        "equipment",
        "同期录音基础设备套装，共 5 套可供借用。",
        5,
        true,
        5,
    ),
    (
        "同期拾音设备进阶套装",
        "equipment",
        "同期录音高端进阶设备套装，仅 1 套，需注明整体使用时间。",
        1,
        true,
        6,
    ),
];

pub fn seed(conn: &Connection) -> rusqlite::Result<()> {
    let slot_count: i64 = conn.query_row("SELECT COUNT(*) FROM time_slots", [], |r| r.get(0))?;
    if slot_count == 0 {
        for (name, start, end, order) in DEFAULT_SLOTS {
            conn.execute(
                "INSERT INTO time_slots (name, start_time, end_time, sort_order, is_active) VALUES (?1, ?2, ?3, ?4, 1)",
                params![name, start, end, order],
            )?;
        }
    }

    let res_count: i64 = conn.query_row("SELECT COUNT(*) FROM resources", [], |r| r.get(0))?;
    if res_count == 0 {
        for (name, kind, desc, qty, individual, order) in DEFAULT_RESOURCES {
            conn.execute(
                "INSERT INTO resources (name, kind, description, image_url, total_quantity, individual_bookable, sort_order, is_active, created_at)
                 VALUES (?1, ?2, ?3, '', ?4, ?5, ?6, 1, ?7)",
                params![name, kind, desc, qty, *individual as i64, order, now_iso()],
            )?;
        }
    }
    Ok(())
}
