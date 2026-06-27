use rusqlite::{params, Connection, OptionalExtension, Row};

use crate::models::{Booking, Resource, Slot};

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
            verified_at TEXT
        );
        "#,
    )
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
        "INSERT INTO resources (name, kind, description, image_url, total_quantity, individual_bookable, sort_order, is_active, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        params![
            r.name, r.kind, r.description, r.image_url, r.total_quantity,
            r.individual_bookable as i64, r.sort_order, r.is_active as i64, now_iso()
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
        "UPDATE resources SET name=?1, kind=?2, description=?3, image_url=?4, total_quantity=?5, individual_bookable=?6, sort_order=?7, is_active=?8 WHERE id=?9",
        params![
            u.name.clone().unwrap_or_else(|| current.name.clone()),
            u.kind.clone().unwrap_or_else(|| current.kind.clone()),
            u.description.clone().unwrap_or_else(|| current.description.clone()),
            u.image_url.clone().unwrap_or_else(|| current.image_url.clone()),
            u.total_quantity.unwrap_or(current.total_quantity),
            u.individual_bookable.unwrap_or(current.individual_bookable) as i64,
            u.sort_order.unwrap_or(current.sort_order),
            u.is_active.unwrap_or(current.is_active) as i64,
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
) -> rusqlite::Result<Booking> {
    conn.execute(
        "UPDATE bookings SET status = ?1, verified_at = ?2 WHERE id = ?3",
        params![status, verified_at, id],
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
