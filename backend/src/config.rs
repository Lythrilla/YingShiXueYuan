use std::env;
use std::path::{Path, PathBuf};

use serde::Deserialize;

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
    /// 开门提醒：提前多少分钟提醒负责人。
    pub reminder_lead_minutes: i64,
    /// 开门提醒所用时区相对 UTC 的小时偏移（中国为 +8）。
    pub tz_offset_hours: i64,
    /// 是否启用开门提醒。
    pub reminder_enabled: bool,
}

/// 配置文件（config.toml）中可选字段。缺省字段使用内置默认值。
#[derive(Debug, Default, Deserialize)]
struct FileConfig {
    admin_username: Option<String>,
    admin_password: Option<String>,
    secret_key: Option<String>,
    token_max_age: Option<i64>,
    host: Option<String>,
    port: Option<u16>,
    open_browser: Option<bool>,
    reminder_lead_minutes: Option<i64>,
    tz_offset_hours: Option<i64>,
    reminder_enabled: Option<bool>,
}

const DEFAULT_ADMIN_USERNAME: &str = "admin";
const DEFAULT_ADMIN_PASSWORD: &str = "admin123";
const DEFAULT_SECRET_KEY: &str = "yingshi-recording-lab-secret-key-change-me";
const DEFAULT_TOKEN_MAX_AGE: i64 = 60 * 60 * 12;
const DEFAULT_HOST: &str = "127.0.0.1";
const DEFAULT_PORT: u16 = 8010;
const DEFAULT_REMINDER_LEAD_MINUTES: i64 = 10;
const DEFAULT_TZ_OFFSET_HOURS: i64 = 8;

/// 首次运行时写入的配置文件模板（带中文注释，便于直接修改）。
const CONFIG_TEMPLATE: &str = r#"# 录音实验室预约系统 配置文件
# 修改后重启程序即可生效。
# 注：同名环境变量（如 ADMIN_PASSWORD）会覆盖此文件中的对应配置。

# 管理员登录账号
admin_username = "admin"
# 管理员登录密码（请务必修改成自己的密码）
admin_password = "admin123"
# 登录令牌签名密钥（建议改成一段随机字符串）
secret_key = "yingshi-recording-lab-secret-key-change-me"
# 登录令牌有效期（秒），默认 43200 = 12 小时
token_max_age = 43200
# 监听地址；如需局域网内其他设备访问，改为 "0.0.0.0"
host = "127.0.0.1"
# 监听端口
port = 8010
# 启动时是否自动打开浏览器
open_browser = true
# 是否启用「开门提醒」：到预约时间前提醒负责人去开门
reminder_enabled = true
# 开门提醒提前量（分钟）
reminder_lead_minutes = 10
# 开门提醒计算所用时区（相对 UTC 的小时偏移，中国为 8）
tz_offset_hours = 8
"#;

impl Config {
    pub fn from_env() -> Self {
        let file = load_or_create_config_file();

        let data_dir = match env::var("DATA_DIR") {
            Ok(dir) => PathBuf::from(dir),
            Err(_) => default_data_dir(),
        };
        let _ = std::fs::create_dir_all(&data_dir);

        let db_path = env::var("DATABASE_PATH")
            .map(PathBuf::from)
            .unwrap_or_else(|_| data_dir.join("booking.db"));

        Config {
            admin_username: env::var("ADMIN_USERNAME")
                .ok()
                .or(file.admin_username)
                .unwrap_or_else(|| DEFAULT_ADMIN_USERNAME.to_string()),
            admin_password: env::var("ADMIN_PASSWORD")
                .ok()
                .or(file.admin_password)
                .unwrap_or_else(|| DEFAULT_ADMIN_PASSWORD.to_string()),
            secret_key: env::var("SECRET_KEY")
                .ok()
                .or(file.secret_key)
                .unwrap_or_else(|| DEFAULT_SECRET_KEY.to_string()),
            token_max_age: env::var("TOKEN_MAX_AGE")
                .ok()
                .and_then(|v| v.parse().ok())
                .or(file.token_max_age)
                .unwrap_or(DEFAULT_TOKEN_MAX_AGE),
            host: env::var("HOST")
                .ok()
                .or(file.host)
                .unwrap_or_else(|| DEFAULT_HOST.to_string()),
            port: env::var("PORT")
                .ok()
                .and_then(|v| v.parse().ok())
                .or(file.port)
                .unwrap_or(DEFAULT_PORT),
            data_dir,
            db_path,
            // 默认在交互式运行时自动打开浏览器；可用 NO_OPEN=1 或配置文件中的
            // open_browser=false 关闭。环境变量优先级更高。
            open_browser: if env::var("NO_OPEN").is_ok() {
                false
            } else {
                file.open_browser.unwrap_or(true)
            },
            reminder_lead_minutes: env::var("REMINDER_LEAD_MINUTES")
                .ok()
                .and_then(|v| v.parse().ok())
                .or(file.reminder_lead_minutes)
                .unwrap_or(DEFAULT_REMINDER_LEAD_MINUTES),
            tz_offset_hours: env::var("TZ_OFFSET_HOURS")
                .ok()
                .and_then(|v| v.parse().ok())
                .or(file.tz_offset_hours)
                .unwrap_or(DEFAULT_TZ_OFFSET_HOURS),
            reminder_enabled: env::var("REMINDER_ENABLED")
                .ok()
                .and_then(|v| v.parse().ok())
                .or(file.reminder_enabled)
                .unwrap_or(true),
        }
    }
}

/// 读取可执行文件同级的 `config.toml`；若不存在则生成一份带注释的模板再读取。
fn load_or_create_config_file() -> FileConfig {
    let path = config_file_path();

    if !path.exists() {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        match std::fs::write(&path, CONFIG_TEMPLATE) {
            Ok(_) => println!("已生成默认配置文件： {path:?}（可在其中修改管理员账号/密码等）"),
            Err(e) => eprintln!("写入配置文件 {path:?} 失败：{e}"),
        }
    }

    match std::fs::read_to_string(&path) {
        Ok(text) => match toml::from_str::<FileConfig>(&text) {
            Ok(cfg) => cfg,
            Err(e) => {
                eprintln!("解析配置文件 {path:?} 失败，将使用默认配置：{e}");
                FileConfig::default()
            }
        },
        Err(_) => FileConfig::default(),
    }
}

/// 配置文件路径：可执行文件同级的 `config.toml`，可用 `CONFIG_PATH` 覆盖。
fn config_file_path() -> PathBuf {
    if let Ok(p) = env::var("CONFIG_PATH") {
        return PathBuf::from(p);
    }
    exe_dir().join("config.toml")
}

/// 数据库与静态资源默认放在可执行文件同级的 `data/` 目录，方便绿色单文件部署。
fn default_data_dir() -> PathBuf {
    exe_dir().join("data")
}

/// 可执行文件所在目录，获取失败时回退到当前工作目录。
fn exe_dir() -> PathBuf {
    if let Ok(exe) = env::current_exe() {
        if let Some(parent) = exe.parent() {
            return parent.to_path_buf();
        }
    }
    Path::new(".").to_path_buf()
}
