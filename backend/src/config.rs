use std::env;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub admin_username: String,
    pub admin_password: String,
    pub secret_key: String,
    pub token_max_age: i64,
    pub host: String,
    pub port: u16,
    pub data_dir: PathBuf,
    pub db_path: PathBuf,
    pub open_browser: bool,
}

impl Config {
    pub fn from_env() -> Self {
        let data_dir = match env::var("DATA_DIR") {
            Ok(dir) => PathBuf::from(dir),
            Err(_) => default_data_dir(),
        };
        let _ = std::fs::create_dir_all(&data_dir);

        let db_path = env::var("DATABASE_PATH")
            .map(PathBuf::from)
            .unwrap_or_else(|_| data_dir.join("booking.db"));

        Config {
            admin_username: env::var("ADMIN_USERNAME").unwrap_or_else(|_| "admin".to_string()),
            admin_password: env::var("ADMIN_PASSWORD").unwrap_or_else(|_| "admin123".to_string()),
            secret_key: env::var("SECRET_KEY")
                .unwrap_or_else(|_| "yingshi-recording-lab-secret-key-change-me".to_string()),
            token_max_age: env::var("TOKEN_MAX_AGE")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(60 * 60 * 12),
            host: env::var("HOST").unwrap_or_else(|_| "127.0.0.1".to_string()),
            port: env::var("PORT")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(8010),
            data_dir,
            db_path,
            // 默认在交互式运行时自动打开浏览器，可用 NO_OPEN=1 关闭
            open_browser: env::var("NO_OPEN").is_err(),
        }
    }
}

/// 数据库与静态资源默认放在可执行文件同级的 `data/` 目录，方便绿色单文件部署。
fn default_data_dir() -> PathBuf {
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            return parent.join("data");
        }
    }
    PathBuf::from("data")
}
