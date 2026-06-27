# 录音实验室预约系统

影视学院录音实验室 / 拾音设备在线预约与核销系统。前台支持按日期、时段预约录音棚与设备，
后台支持资源管理、时间段管理、预约核销与 Excel 报表导出。

## 技术栈

- **后端**：Rust + axum + rusqlite（内置 SQLite）+ rust_xlsxwriter（Excel 导出）
- **前端**：React + Vite + TypeScript + Tailwind CSS
- 前端静态资源在编译期通过 `rust-embed` 嵌入后端二进制，最终产出**单个可执行文件**（Windows `.exe`），双击即用、自带数据库，无需安装 Python / Node 运行时。

## 目录结构

```
backend/    Rust 后端 API（同时内嵌并托管前端静态页面）
frontend/   React 前台预约 + 后台管理界面
scripts/    构建脚本（打包前端 + 交叉编译 .exe）
```

## 打包成单文件 exe

```bash
# 在 Linux 上交叉编译（需先安装下列依赖）
rustup target add x86_64-pc-windows-gnu
sudo apt-get install -y gcc-mingw-w64-x86-64

./scripts/build-exe.sh        # 产物：dist/录音实验室预约系统.exe
```

双击 exe 即启动服务并自动打开浏览器（`http://127.0.0.1:8010`），前台、后台与 `/api` 共用同一端口。数据库自动建在 exe 同级的 `data/booking.db`。

> 在 Windows 上本机构建只需 `cd backend && cargo build --release`（构建前先执行一次前端 `npm run build`）。

## 本地开发

### 后端

```bash
cd frontend && npm install && npm run build   # 先生成 frontend/dist 供后端嵌入
cd ../backend
cargo run                                     # 监听 http://127.0.0.1:8010
```

首次启动会自动建表并写入默认实验室、设备与时间段数据（数据库位于 `backend/data/booking.db`）。

### 前端

```bash
cd frontend
npm install
npm run dev      # http://localhost:5173
```

开发服务器已将 `/api` 代理到 `http://127.0.0.1:8010`。

## 功能

### 前台（`/`）
- 选择日期（可提前 7 天）与时段进行预约
- 录音实验室、拾音设备分组展示，实时显示每时段剩余名额
- 预约表单：姓名、电话、专业、人数、指导教师、用途、数量

### 后台（`/admin`）
- 管理员登录（默认账号 `admin` / `admin123`）
- 预约管理：筛选（状态 / 资源 / 日期 / 关键词）、核销、取消
- 数据概览：总预约、待核销、已核销、已取消、今日预约
- 资源管理：实验室 / 设备的增删改（名额、是否允许个人预约、上架状态等）
- 时间段管理：增删改
- 一键导出 Excel 报表

## 配置

### 配置文件（推荐）

首次启动时，程序会在**可执行文件同级目录**自动生成一份 `config.toml`，可直接编辑其中的管理员账号 / 密码、端口等，**修改后重启程序即可生效**：

```toml
admin_username = "admin"
admin_password = "admin123"   # 请务必修改成自己的密码
secret_key = "yingshi-recording-lab-secret-key-change-me"
token_max_age = 43200          # 登录令牌有效期（秒），默认 12 小时
host = "127.0.0.1"             # 局域网访问改为 "0.0.0.0"
port = 8010
open_browser = true            # 启动时是否自动打开浏览器
```

可用 `CONFIG_PATH` 环境变量指定其他配置文件路径。

### 环境变量（优先级高于配置文件）

下列环境变量会覆盖配置文件与默认值：

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `ADMIN_USERNAME` | 管理员用户名 | `admin` |
| `ADMIN_PASSWORD` | 管理员密码 | `admin123` |
| `SECRET_KEY` | 令牌签名密钥（HMAC-SHA256） | 内置开发密钥 |
| `TOKEN_MAX_AGE` | 登录令牌有效期（秒） | `43200`（12 小时） |
| `HOST` | 监听地址 | `127.0.0.1` |
| `PORT` | 监听端口 | `8010` |
| `DATA_DIR` | 数据库所在目录 | exe 同级 `data/` |
| `NO_OPEN` | 设为任意值则启动时不自动打开浏览器 | 未设置 |

前端可提前预约天数由 `frontend/src/lib.ts` 中的 `BOOKING_WINDOW_DAYS` 控制（默认 `7`）。
