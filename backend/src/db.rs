use rusqlite::{params, Connection, OptionalExtension, Row};

use crate::models::{
    Admin, Booking, DutyShift, LabeledCount, OperationLog, Resource, Slot, StatsReport,
};

pub fn open(path: &std::path::Path) -> rusqlite::Result<Connection> {
    let conn = Connection::open(path)?;
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    Ok(conn)
}

pub fn init_schema(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS resources (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'lab',
            description TEXT NOT NULL DEFAULT '',
            image_url TEXT NOT NULL DEFAULT '',
            total_quantity INTEGER NOT NULL DEFAULT 1,
            individual_bookable INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS time_slots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE IF NOT EXISTS bookings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            resource_id INTEGER NOT NULL REFERENCES resources(id) ON DELETE CASCADE,
            slot_id INTEGER NOT NULL REFERENCES time_slots(id) ON DELETE CASCADE,
            date TEXT NOT NULL,
            applicant_name TEXT NOT NULL,
            phone TEXT NOT NULL,
            major TEXT NOT NULL DEFAULT '',
            num_people INTEGER NOT NULL DEFAULT 1,
            instructor TEXT NOT NULL DEFAULT '',
            description TEXT NOT NULL DEFAULT '',
            quantity INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'booked',
            created_at TEXT NOT NULL DEFAULT '',
            verified_at TEXT,
            admin_note TEXT NOT NULL DEFAULT '',
            processed_by TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS admins (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'staff',
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS operation_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            actor TEXT NOT NULL DEFAULT '',
            action TEXT NOT NULL DEFAULT '',
            target TEXT NOT NULL DEFAULT '',
            detail TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS duty_shifts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            weekday INTEGER NOT NULL DEFAULT -1,
            slot_id INTEGER NOT NULL DEFAULT 0,
            resource_id INTEGER NOT NULL DEFAULT 0,
            admin_username TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT ''
        );
        "#,
    )?;
    // 兼容旧数据库：补齐后加的列。
    add_column_if_missing(conn, "bookings", "admin_note", "TEXT NOT NULL DEFAULT ''")?;
    add_column_if_missing(conn, "bookings", "processed_by", "TEXT NOT NULL DEFAULT ''")?;
    add_column_if_missing(conn, "bookings", "reminded_at", "TEXT")?;
    add_column_if_missing(conn, "resources", "manager", "TEXT NOT NULL DEFAULT ''")?;
    Ok(())
}

/// SQLite 没有 `ADD COLUMN IF NOT EXISTS`，这里手动检查后再补列。
fn add_column_if_missing(
    conn: &Connection,
    table: &str,
    column: &str,
    decl: &str,
) -> rusqlite::Result<()> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    let existing: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<rusqlite::Result<_>>()?;
    if !existing.iter().any(|c| c == column) {
        conn.execute(
            &format!("ALTER TABLE {table} ADD COLUMN {column} {decl}"),
            [],
        )?;
    }
    Ok(())
}

pub fn now_iso() -> String {
    chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S").to_string()
}

pub fn today_str() -> String {
    chrono::Utc::now().format("%Y-%m-%d").to_string()
}

// ---------- Mapping ----------
fn map_resource(row: &Row) -> rusqlite::Result<Resource> {
    Ok(Resource {
        id: row.get("id")?,
        name: row.get("name")?,
        kind: row.get("kind")?,
        description: row.get("description")?,
        image_url: row.get("image_url")?,
        total_quantity: row.get("total_quantity")?,
        individual_bookable: row.get::<_, i64>("individual_bookable")? != 0,
        sort_order: row.get("sort_order")?,
        is_active: row.get::<_, i64>("is_active")? != 0,
        manager: row.get("manager")?,
    })
}

fn map_slot(row: &Row) -> rusqlite::Result<Slot> {
    Ok(Slot {
        id: row.get("id")?,
        name: row.get("name")?,
        start_time: row.get("start_time")?,
        end_time: row.get("end_time")?,
        sort_order: row.get("sort_order")?,
        is_active: row.get::<_, i64>("is_active")? != 0,
    })
}

// ---------- Resources ----------
pub fn list_resources(conn: &Connection, active_only: bool) -> rusqlite::Result<Vec<Resource>> {
    let sql = if active_only {
        "SELECT * FROM resources WHERE is_active = 1 ORDER BY sort_order, id"
    } else {
        "SELECT * FROM resources ORDER BY sort_order, id"
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map([], map_resource)?;
    rows.collect()
}

pub fn get_resource(conn: &Connection, id: i64) -> rusqlite::Result<Option<Resource>> {
    conn.query_row("SELECT * FROM resources WHERE id = ?1", [id], map_resource)
        .optional()
}

pub fn create_resource(
    conn: &Connection,
    r: &crate::models::ResourceCreate,
) -> rusqlite::Result<Resource> {
    conn.execute(
        "INSERT INTO resources (name, kind, description, image_url, total_quantity, individual_bookable, sort_order, is_active, manager, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
        params![
            r.name, r.kind, r.description, r.image_url, r.total_quantity,
            r.individual_bookable as i64, r.sort_order, r.is_active as i64, r.manager, now_iso()
        ],
    )?;
    let id = conn.last_insert_rowid();
    Ok(get_resource(conn, id)?.expect("just inserted"))
}

pub fn update_resource(
    conn: &Connection,
    current: &Resource,
    u: &crate::models::ResourceUpdate,
) -> rusqlite::Result<Resource> {
    conn.execute(
        "UPDATE resources SET name=?1, kind=?2, description=?3, image_url=?4, total_quantity=?5, individual_bookable=?6, sort_order=?7, is_active=?8, manager=?9 WHERE id=?10",
        params![
            u.name.clone().unwrap_or_else(|| current.name.clone()),
            u.kind.clone().unwrap_or_else(|| current.kind.clone()),
            u.description.clone().unwrap_or_else(|| current.description.clone()),
            u.image_url.clone().unwrap_or_else(|| current.image_url.clone()),
            u.total_quantity.unwrap_or(current.total_quantity),
            u.individual_bookable.unwrap_or(current.individual_bookable) as i64,
            u.sort_order.unwrap_or(current.sort_order),
            u.is_active.unwrap_or(current.is_active) as i64,
            u.manager.clone().unwrap_or_else(|| current.manager.clone()),
            current.id,
        ],
    )?;
    Ok(get_resource(conn, current.id)?.expect("just updated"))
}

pub fn delete_resource(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM resources WHERE id = ?1", [id])?;
    Ok(())
}

// ---------- Slots ----------
pub fn list_slots(conn: &Connection, active_only: bool) -> rusqlite::Result<Vec<Slot>> {
    let sql = if active_only {
        "SELECT * FROM time_slots WHERE is_active = 1 ORDER BY sort_order, id"
    } else {
        "SELECT * FROM time_slots ORDER BY sort_order, id"
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map([], map_slot)?;
    rows.collect()
}

pub fn get_slot(conn: &Connection, id: i64) -> rusqlite::Result<Option<Slot>> {
    conn.query_row("SELECT * FROM time_slots WHERE id = ?1", [id], map_slot)
        .optional()
}

pub fn create_slot(conn: &Connection, s: &crate::models::SlotCreate) -> rusqlite::Result<Slot> {
    conn.execute(
        "INSERT INTO time_slots (name, start_time, end_time, sort_order, is_active) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![s.name, s.start_time, s.end_time, s.sort_order, s.is_active as i64],
    )?;
    let id = conn.last_insert_rowid();
    Ok(get_slot(conn, id)?.expect("just inserted"))
}

pub fn update_slot(
    conn: &Connection,
    current: &Slot,
    u: &crate::models::SlotUpdate,
) -> rusqlite::Result<Slot> {
    conn.execute(
        "UPDATE time_slots SET name=?1, start_time=?2, end_time=?3, sort_order=?4, is_active=?5 WHERE id=?6",
        params![
            u.name.clone().unwrap_or_else(|| current.name.clone()),
            u.start_time.clone().unwrap_or_else(|| current.start_time.clone()),
            u.end_time.clone().unwrap_or_else(|| current.end_time.clone()),
            u.sort_order.unwrap_or(current.sort_order),
            u.is_active.unwrap_or(current.is_active) as i64,
            current.id,
        ],
    )?;
    Ok(get_slot(conn, current.id)?.expect("just updated"))
}

pub fn delete_slot(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM time_slots WHERE id = ?1", [id])?;
    Ok(())
}

// ---------- Bookings ----------
pub fn booked_quantity(
    conn: &Connection,
    resource_id: i64,
    slot_id: i64,
    date: &str,
) -> rusqlite::Result<i64> {
    let total: i64 = conn.query_row(
        "SELECT COALESCE(SUM(quantity), 0) FROM bookings
         WHERE resource_id = ?1 AND slot_id = ?2 AND date = ?3 AND status != 'cancelled'",
        params![resource_id, slot_id, date],
        |row| row.get(0),
    )?;
    Ok(total)
}

#[derive(Default)]
pub struct BookingFilter {
    pub status: Option<String>,
    pub resource_id: Option<i64>,
    pub date: Option<String>,
    pub keyword: Option<String>,
    pub phone: Option<String>,
}

fn hydrate_booking(conn: &Connection, row: &Row) -> rusqlite::Result<Booking> {
    let resource_id: i64 = row.get("resource_id")?;
    let slot_id: i64 = row.get("slot_id")?;
    let resource = get_resource(conn, resource_id)?;
    let slot = get_slot(conn, slot_id)?;
    Ok(Booking {
        id: row.get("id")?,
        resource_id,
        slot_id,
        date: row.get("date")?,
        applicant_name: row.get("applicant_name")?,
        phone: row.get("phone")?,
        major: row.get("major")?,
        num_people: row.get("num_people")?,
        instructor: row.get("instructor")?,
        description: row.get("description")?,
        quantity: row.get("quantity")?,
        status: row.get("status")?,
        created_at: row.get("created_at")?,
        verified_at: row.get("verified_at")?,
        admin_note: row.get("admin_note")?,
        processed_by: row.get("processed_by")?,
        resource: resource.expect("booking references an existing resource"),
        slot: slot.expect("booking references an existing slot"),
    })
}

pub fn list_bookings(conn: &Connection, f: &BookingFilter) -> rusqlite::Result<Vec<Booking>> {
    let mut sql = String::from("SELECT * FROM bookings WHERE 1=1");
    let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
    if let Some(s) = &f.status {
        sql.push_str(" AND status = ?");
        args.push(Box::new(s.clone()));
    }
    if let Some(rid) = f.resource_id {
        sql.push_str(" AND resource_id = ?");
        args.push(Box::new(rid));
    }
    if let Some(d) = &f.date {
        sql.push_str(" AND date = ?");
        args.push(Box::new(d.clone()));
    }
    if let Some(p) = &f.phone {
        sql.push_str(" AND phone = ?");
        args.push(Box::new(p.clone()));
    }
    if let Some(k) = &f.keyword {
        sql.push_str(" AND (applicant_name LIKE ? OR phone LIKE ? OR instructor LIKE ?)");
        let like = format!("%{}%", k);
        args.push(Box::new(like.clone()));
        args.push(Box::new(like.clone()));
        args.push(Box::new(like));
    }
    sql.push_str(" ORDER BY date DESC, id DESC");

    let mut stmt = conn.prepare(&sql)?;
    let param_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
    let mut rows = stmt.query(param_refs.as_slice())?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(hydrate_booking(conn, row)?);
    }
    Ok(out)
}

pub fn get_booking(conn: &Connection, id: i64) -> rusqlite::Result<Option<Booking>> {
    let mut stmt = conn.prepare("SELECT * FROM bookings WHERE id = ?1")?;
    let mut rows = stmt.query([id])?;
    match rows.next()? {
        Some(row) => Ok(Some(hydrate_booking(conn, row)?)),
        None => Ok(None),
    }
}

pub fn create_booking(
    conn: &Connection,
    b: &crate::models::BookingCreate,
) -> rusqlite::Result<Booking> {
    conn.execute(
        "INSERT INTO bookings (resource_id, slot_id, date, applicant_name, phone, major, num_people, instructor, description, quantity, status, created_at, verified_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'booked', ?11, NULL)",
        params![
            b.resource_id, b.slot_id, b.date, b.applicant_name, b.phone, b.major,
            b.num_people, b.instructor, b.description, b.quantity, now_iso()
        ],
    )?;
    let id = conn.last_insert_rowid();
    Ok(get_booking(conn, id)?.expect("just inserted"))
}

pub fn set_booking_status(
    conn: &Connection,
    id: i64,
    status: &str,
    verified_at: Option<String>,
    note: &str,
    processed_by: &str,
) -> rusqlite::Result<Booking> {
    conn.execute(
        "UPDATE bookings SET status = ?1, verified_at = ?2, admin_note = ?3, processed_by = ?4 WHERE id = ?5",
        params![status, verified_at, note, processed_by, id],
    )?;
    Ok(get_booking(conn, id)?.expect("just updated"))
}

pub struct Stats {
    pub total: i64,
    pub booked: i64,
    pub verified: i64,
    pub cancelled: i64,
    pub today: i64,
}

pub fn stats(conn: &Connection) -> rusqlite::Result<Stats> {
    let total: i64 = conn.query_row("SELECT COUNT(*) FROM bookings", [], |r| r.get(0))?;
    let booked: i64 = conn.query_row(
        "SELECT COUNT(*) FROM bookings WHERE status='booked'",
        [],
        |r| r.get(0),
    )?;
    let verified: i64 = conn.query_row(
        "SELECT COUNT(*) FROM bookings WHERE status='verified'",
        [],
        |r| r.get(0),
    )?;
    let cancelled: i64 = conn.query_row(
        "SELECT COUNT(*) FROM bookings WHERE status='cancelled'",
        [],
        |r| r.get(0),
    )?;
    let today: i64 = conn.query_row(
        "SELECT COUNT(*) FROM bookings WHERE date=?1 AND status != 'cancelled'",
        [today_str()],
        |r| r.get(0),
    )?;
    Ok(Stats {
        total,
        booked,
        verified,
        cancelled,
        today,
    })
}

/// 更丰富的统计报表：本周/本月、近 14 天趋势、按资源 / 时段分布（均不含已取消）。
pub fn stats_report(conn: &Connection) -> rusqlite::Result<StatsReport> {
    let base = stats(conn)?;

    let active = "status != 'cancelled'";
    let count_since = |from: &str| -> rusqlite::Result<i64> {
        conn.query_row(
            &format!("SELECT COUNT(*) FROM bookings WHERE date >= ?1 AND {active}"),
            [from],
            |r| r.get(0),
        )
    };
    let now = chrono::Utc::now();
    let week_start = (now - chrono::Duration::days(6))
        .format("%Y-%m-%d")
        .to_string();
    let month_start = now.format("%Y-%m-01").to_string();
    let this_week = count_since(&week_start)?;
    let this_month = count_since(&month_start)?;

    // 近 14 天趋势（按预约日期）。
    let mut trend = Vec::with_capacity(14);
    for i in (0..14).rev() {
        let d = (now - chrono::Duration::days(i)).format("%Y-%m-%d").to_string();
        let value: i64 = conn.query_row(
            &format!("SELECT COUNT(*) FROM bookings WHERE date = ?1 AND {active}"),
            [&d],
            |r| r.get(0),
        )?;
        let label = format!("{}/{}", &d[5..7], &d[8..10]);
        trend.push(LabeledCount { label, value });
    }

    let mut by_resource = Vec::new();
    {
        let mut stmt = conn.prepare(
            "SELECT r.name, COUNT(b.id) FROM resources r
             LEFT JOIN bookings b ON b.resource_id = r.id AND b.status != 'cancelled'
             GROUP BY r.id ORDER BY r.sort_order, r.id",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(LabeledCount {
                label: row.get(0)?,
                value: row.get(1)?,
            })
        })?;
        for r in rows {
            by_resource.push(r?);
        }
    }
    by_resource.sort_by_key(|c| std::cmp::Reverse(c.value));

    let mut by_slot = Vec::new();
    {
        let mut stmt = conn.prepare(
            "SELECT s.name, COUNT(b.id) FROM time_slots s
             LEFT JOIN bookings b ON b.slot_id = s.id AND b.status != 'cancelled'
             GROUP BY s.id ORDER BY s.sort_order, s.id",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(LabeledCount {
                label: row.get(0)?,
                value: row.get(1)?,
            })
        })?;
        for r in rows {
            by_slot.push(r?);
        }
    }

    Ok(StatsReport {
        total: base.total,
        booked: base.booked,
        verified: base.verified,
        cancelled: base.cancelled,
        today: base.today,
        this_week,
        this_month,
        trend,
        by_resource,
        by_slot,
    })
}

// ---------- Admins（多管理员） ----------
fn map_admin(row: &Row) -> rusqlite::Result<Admin> {
    Ok(Admin {
        id: row.get("id")?,
        username: row.get("username")?,
        role: row.get("role")?,
        is_active: row.get::<_, i64>("is_active")? != 0,
        created_at: row.get("created_at")?,
    })
}

pub fn list_admins(conn: &Connection) -> rusqlite::Result<Vec<Admin>> {
    let mut stmt = conn.prepare("SELECT * FROM admins ORDER BY id")?;
    let rows = stmt.query_map([], map_admin)?;
    rows.collect()
}

pub fn get_admin_by_username(conn: &Connection, username: &str) -> rusqlite::Result<Option<Admin>> {
    conn.query_row("SELECT * FROM admins WHERE username = ?1", [username], map_admin)
        .optional()
}

pub fn admin_password_hash(conn: &Connection, username: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT password_hash FROM admins WHERE username = ?1 AND is_active = 1",
        [username],
        |r| r.get(0),
    )
    .optional()
}

pub fn upsert_admin(
    conn: &Connection,
    username: &str,
    password_hash: &str,
    role: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO admins (username, password_hash, role, is_active, created_at)
         VALUES (?1, ?2, ?3, 1, ?4)
         ON CONFLICT(username) DO UPDATE SET password_hash=excluded.password_hash, role=excluded.role",
        params![username, password_hash, role, now_iso()],
    )?;
    Ok(())
}

pub fn create_admin(
    conn: &Connection,
    username: &str,
    password_hash: &str,
    role: &str,
) -> rusqlite::Result<Admin> {
    conn.execute(
        "INSERT INTO admins (username, password_hash, role, is_active, created_at) VALUES (?1, ?2, ?3, 1, ?4)",
        params![username, password_hash, role, now_iso()],
    )?;
    Ok(get_admin_by_username(conn, username)?.expect("just inserted"))
}

pub fn update_admin(
    conn: &Connection,
    id: i64,
    password_hash: Option<&str>,
    role: Option<&str>,
    is_active: Option<bool>,
) -> rusqlite::Result<Option<Admin>> {
    if let Some(h) = password_hash {
        conn.execute("UPDATE admins SET password_hash=?1 WHERE id=?2", params![h, id])?;
    }
    if let Some(r) = role {
        conn.execute("UPDATE admins SET role=?1 WHERE id=?2", params![r, id])?;
    }
    if let Some(a) = is_active {
        conn.execute(
            "UPDATE admins SET is_active=?1 WHERE id=?2",
            params![a as i64, id],
        )?;
    }
    conn.query_row("SELECT * FROM admins WHERE id = ?1", [id], map_admin)
        .optional()
}

pub fn delete_admin(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM admins WHERE id = ?1", [id])?;
    Ok(())
}

pub fn count_super_admins(conn: &Connection) -> rusqlite::Result<i64> {
    conn.query_row(
        "SELECT COUNT(*) FROM admins WHERE role = 'super' AND is_active = 1",
        [],
        |r| r.get(0),
    )
}

// ---------- Operation logs（操作日志） ----------
pub fn add_log(
    conn: &Connection,
    actor: &str,
    action: &str,
    target: &str,
    detail: &str,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO operation_logs (actor, action, target, detail, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![actor, action, target, detail, now_iso()],
    )?;
    Ok(())
}

pub fn list_logs(conn: &Connection, limit: i64) -> rusqlite::Result<Vec<OperationLog>> {
    let mut stmt = conn.prepare(
        "SELECT id, actor, action, target, detail, created_at FROM operation_logs ORDER BY id DESC LIMIT ?1",
    )?;
    let rows = stmt.query_map([limit], |row| {
        Ok(OperationLog {
            id: row.get(0)?,
            actor: row.get(1)?,
            action: row.get(2)?,
            target: row.get(3)?,
            detail: row.get(4)?,
            created_at: row.get(5)?,
        })
    })?;
    rows.collect()
}

// ---------- Duty shifts（排班 / 开门负责人） ----------
fn map_shift(row: &Row) -> rusqlite::Result<DutyShift> {
    Ok(DutyShift {
        id: row.get("id")?,
        weekday: row.get("weekday")?,
        slot_id: row.get("slot_id")?,
        resource_id: row.get("resource_id")?,
        admin_username: row.get("admin_username")?,
        created_at: row.get("created_at")?,
    })
}

pub fn list_shifts(conn: &Connection) -> rusqlite::Result<Vec<DutyShift>> {
    let mut stmt = conn.prepare(
        "SELECT * FROM duty_shifts ORDER BY weekday, slot_id, resource_id, id",
    )?;
    let rows = stmt.query_map([], map_shift)?;
    rows.collect()
}

pub fn create_shift(
    conn: &Connection,
    weekday: i64,
    slot_id: i64,
    resource_id: i64,
    admin_username: &str,
) -> rusqlite::Result<DutyShift> {
    conn.execute(
        "INSERT INTO duty_shifts (weekday, slot_id, resource_id, admin_username, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![weekday, slot_id, resource_id, admin_username, now_iso()],
    )?;
    let id = conn.last_insert_rowid();
    conn.query_row("SELECT * FROM duty_shifts WHERE id = ?1", [id], map_shift)
}

pub fn delete_shift(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM duty_shifts WHERE id = ?1", [id])?;
    Ok(())
}

/// 解析某次预约的当值负责人：在所有命中的排班里取最精确的一条。
/// 命中条件：weekday 为 -1（每天）或等于该日星期；slot_id 为 0（全部）或匹配；resource_id 同理。
/// 精确度 = 指定了具体星期 + 具体时段 + 具体资源 的数量，越高越优先。
pub fn resolve_duty(
    conn: &Connection,
    weekday: i64,
    slot_id: i64,
    resource_id: i64,
) -> rusqlite::Result<Option<String>> {
    let mut stmt = conn.prepare(
        "SELECT admin_username,
                (weekday != -1) + (slot_id != 0) + (resource_id != 0) AS specificity
         FROM duty_shifts
         WHERE (weekday = -1 OR weekday = ?1)
           AND (slot_id = 0 OR slot_id = ?2)
           AND (resource_id = 0 OR resource_id = ?3)
         ORDER BY specificity DESC, id ASC
         LIMIT 1",
    )?;
    let found: Option<String> = stmt
        .query_row(params![weekday, slot_id, resource_id], |row| row.get(0))
        .optional()?;
    Ok(found)
}

// ---------- Door reminders（开门提醒） ----------
/// 今天还没提醒过、且未取消的预约（已 hydrate，含 slot 起始时间）。
pub fn unreminded_bookings_on(conn: &Connection, date: &str) -> rusqlite::Result<Vec<Booking>> {
    let mut stmt = conn.prepare(
        "SELECT * FROM bookings WHERE date = ?1 AND status != 'cancelled' AND reminded_at IS NULL ORDER BY id",
    )?;
    let mut rows = stmt.query([date])?;
    let mut out = Vec::new();
    while let Some(row) = rows.next()? {
        out.push(hydrate_booking(conn, row)?);
    }
    Ok(out)
}

pub fn mark_reminded(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE bookings SET reminded_at = ?1 WHERE id = ?2",
        params![now_iso(), id],
    )?;
    Ok(())
}
