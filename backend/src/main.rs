mod auth;
mod config;
mod db;
mod error;
mod excel;
mod handlers;
mod models;
mod push;
mod reminder;
mod seed;
mod web;

use std::sync::{Arc, Mutex};

use axum::{
    routing::{delete, get, post, put},
    Router,
};
use tower_http::compression::CompressionLayer;
use tower_http::cors::{Any, CorsLayer};

use config::Config;
use handlers::AppState;

#[tokio::main]
async fn main() {
    let config = Config::from_env();

    let conn = db::open(&config.db_path).unwrap_or_else(|e| {
        eprintln!("无法打开数据库 {:?}: {e}", config.db_path);
        std::process::exit(1);
    });
    db::init_schema(&conn).expect("初始化数据库表失败");
    seed::seed(&conn).expect("写入默认数据失败");
    // 把配置文件里的内置管理员同步进 admins 表（恒为超级管理员）。
    let admin_hash = auth::hash_password(&config.secret_key, &config.admin_password);
    db::upsert_admin(&conn, &config.admin_username, &admin_hash, "super")
        .expect("初始化内置管理员失败");

    let (events, _) = tokio::sync::broadcast::channel::<String>(256);
    let state = AppState {
        db: Arc::new(Mutex::new(conn)),
        config: Arc::new(config.clone()),
        events,
        reminder_wake: Arc::new(tokio::sync::Notify::new()),
    };

    let api = Router::new()
        // public
        .route("/api/resources", get(handlers::list_resources))
        .route("/api/slots", get(handlers::list_slots))
        .route("/api/availability/:id", get(handlers::availability))
        .route("/api/bookings", post(handlers::create_booking))
        .route("/api/my-bookings", get(handlers::my_bookings))
        // admin auth
        .route("/api/admin/login", post(handlers::login))
        .route("/api/admin/me", get(handlers::me))
        // 实时推送（SSE）
        .route("/api/admin/events", get(handlers::admin_events))
        // 厂商离线推送令牌登记
        .route("/api/admin/push/register", post(handlers::push_register))
        .route("/api/admin/push/unregister", post(handlers::push_unregister))
        // admin resources
        .route("/api/admin/resources", get(handlers::admin_list_resources))
        .route("/api/admin/resources", post(handlers::create_resource))
        .route("/api/admin/resources/:id", put(handlers::update_resource))
        .route(
            "/api/admin/resources/:id",
            delete(handlers::delete_resource),
        )
        .route("/api/admin/uploads/images", post(handlers::upload_image))
        // admin slots
        .route("/api/admin/slots", get(handlers::admin_list_slots))
        .route("/api/admin/slots", post(handlers::create_slot))
        .route("/api/admin/slots/:id", put(handlers::update_slot))
        .route("/api/admin/slots/:id", delete(handlers::delete_slot))
        // admin bookings
        .route("/api/admin/bookings", get(handlers::admin_list_bookings))
        .route(
            "/api/admin/bookings/:id/verify",
            post(handlers::verify_booking),
        )
        .route(
            "/api/admin/bookings/:id/cancel",
            post(handlers::cancel_booking),
        )
        .route(
            "/api/admin/bookings/:id",
            delete(handlers::delete_booking),
        )
        .route(
            "/api/admin/batch-bookings/:op",
            post(handlers::batch_bookings),
        )
        .route("/api/admin/stats", get(handlers::stats))
        .route("/api/admin/stats/report", get(handlers::stats_report))
        .route("/api/admin/export", get(handlers::export_bookings))
        // admin: 操作日志
        .route("/api/admin/logs", get(handlers::list_logs))
        // admin: 多管理员账号
        .route("/api/admin/admins", get(handlers::list_admins))
        .route("/api/admin/admins", post(handlers::create_admin))
        .route("/api/admin/admins/:id", put(handlers::update_admin))
        .route("/api/admin/admins/:id", delete(handlers::delete_admin))
        // admin: 排班（开门负责人）
        .route("/api/admin/shifts", get(handlers::list_shifts))
        .route("/api/admin/shifts", post(handlers::create_shift))
        .route("/api/admin/shifts/:id", delete(handlers::delete_shift))
        .route("/uploads/images/:filename", get(handlers::uploaded_image))
        .route("/healthz", get(handlers::healthz));

    let app = Router::new()
        .merge(api)
        // 其余路径交给嵌入的前端静态资源（含 SPA 回退）
        .fallback(web::static_handler)
        .layer(CompressionLayer::new())
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .with_state(state.clone());

    // 启动常驻「开门提醒」后台任务。
    tokio::spawn(reminder::run(state));

    let addr = format!("{}:{}", config.host, config.port);
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .unwrap_or_else(|e| {
            eprintln!("无法监听 {addr}: {e}");
            std::process::exit(1);
        });

    let url = format!("http://{}:{}", display_host(&config.host), config.port);
    println!("\n  河北科技大学影视学院录音系 · 录音实验室预约系统已启动");
    println!("  打开浏览器访问： {url}");
    println!("  数据库文件： {:?}", config.db_path);
    println!("  按 Ctrl+C 退出\n");

    if config.open_browser {
        open_browser(&url);
    }

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .expect("服务异常退出");
}

fn display_host(host: &str) -> String {
    if host == "0.0.0.0" {
        "127.0.0.1".to_string()
    } else {
        host.to_string()
    }
}

/// 跨平台尝试打开默认浏览器；失败时静默忽略（例如无 GUI 环境）。
fn open_browser(url: &str) {
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("cmd")
        .args(["/C", "start", "", url])
        .spawn();

    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(url).spawn();

    #[cfg(all(unix, not(target_os = "macos")))]
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}
