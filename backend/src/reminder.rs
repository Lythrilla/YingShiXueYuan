use std::time::Duration;

use chrono::{Datelike, FixedOffset, Timelike, Utc};
use serde_json::json;

use crate::db;
use crate::handlers::AppState;

/// 兜底睡眠上限：即使没有任何待提醒预约，也最多睡到这个时长后重新评估
/// （配合「睡到次日 0 点」实现跨天自动重扫）。
const MAX_SLEEP: Duration = Duration::from_secs(6 * 3600);

/// 事件驱动的开门提醒调度器：始终「睡到下一个提醒时刻」才醒来，
/// 期间有新预约入库会通过 `reminder_wake` 立即唤醒重算，空闲时几乎不耗 CPU。
pub async fn run(state: AppState) {
    loop {
        let sleep_dur = if state.config.reminder_enabled {
            match tick(&state) {
                Ok(d) => d,
                Err(e) => {
                    eprintln!("开门提醒任务出错：{e}");
                    Duration::from_secs(60)
                }
            }
        } else {
            MAX_SLEEP
        };

        tokio::select! {
            _ = tokio::time::sleep(sleep_dur) => {}
            _ = state.reminder_wake.notified() => {}
        }
    }
}

/// 触发所有「已到点」的提醒，并返回距离下一个提醒时刻的睡眠时长。
fn tick(state: &AppState) -> rusqlite::Result<Duration> {
    let offset = FixedOffset::east_opt((state.config.tz_offset_hours * 3600) as i32)
        .unwrap_or_else(|| FixedOffset::east_opt(8 * 3600).expect("valid offset"));
    let now = Utc::now().with_timezone(&offset);
    let today = now.format("%Y-%m-%d").to_string();
    let weekday = now.weekday().num_days_from_sunday() as i64; // 0=周日..6=周六
    let now_sec = now.num_seconds_from_midnight() as i64;
    let lead_sec = state.config.reminder_lead_minutes * 60;

    let due = {
        let conn = state.conn();
        db::unreminded_bookings_on(&conn, &today)?
    };

    // 距离下一个提醒时刻的最短秒数；默认睡到次日 0 点以便跨天重扫。
    let mut next_in = 86400 - now_sec + 30;

    for b in due {
        let Some(start_sec) = parse_hms(&b.slot.start_time) else {
            continue;
        };
        let remind_at = start_sec - lead_sec;

        if now_sec >= remind_at {
            // 已进入提醒窗口；超过开始时间 60 分钟则不再补提（避免重启时补提历史预约），
            // 但仍标记为已提醒，免得反复评估。
            if now_sec <= start_sec + 3600 {
                fire(state, &b, weekday)?;
            }
            let conn = state.conn();
            db::mark_reminded(&conn, b.id)?;
        } else {
            next_in = next_in.min(remind_at - now_sec);
        }
    }

    let secs = next_in.clamp(1, MAX_SLEEP.as_secs() as i64) as u64;
    Ok(Duration::from_secs(secs))
}

/// 解析当值负责人并推送 door_reminder 事件。
fn fire(state: &AppState, b: &crate::models::Booking, weekday: i64) -> rusqlite::Result<()> {
    let duty = {
        let conn = state.conn();
        db::resolve_duty(&conn, weekday, b.slot_id, b.resource_id)?
    };
    // 解析顺序：排班命中 > 资源默认负责人 > 留空（所有管理员都提醒）。
    let duty = duty
        .filter(|s| !s.is_empty())
        .or_else(|| {
            let m = b.resource.manager.trim();
            (!m.is_empty()).then(|| m.to_string())
        })
        .unwrap_or_default();

    let payload = json!({
        "type": "door_reminder",
        "booking_id": b.id,
        "resource": b.resource.name,
        "slot": b.slot.name,
        "start_time": b.slot.start_time,
        "date": b.date,
        "applicant": b.applicant_name,
        "duty": duty,
        "ts": db::now_iso(),
    });
    let _ = state.events.send(payload.to_string());
    Ok(())
}

/// 解析 "HH:MM" 或 "HH:MM:SS" 为当天的秒数。
fn parse_hms(s: &str) -> Option<i64> {
    let mut it = s.trim().split(':');
    let h: i64 = it.next()?.trim().parse().ok()?;
    let m: i64 = it.next()?.trim().parse().ok()?;
    let sec: i64 = it.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0);
    Some(h * 3600 + m * 60 + sec)
}
