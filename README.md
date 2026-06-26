# 录音实验室预约系统

影视学院录音实验室 / 拾音设备在线预约与核销系统。前台支持按日期、时段预约录音棚与设备，
后台支持资源管理、时间段管理、预约核销与 Excel 报表导出。

## 技术栈

- **后端**：FastAPI + SQLAlchemy（SQLite）+ openpyxl（Excel 导出）
- **前端**：React + Vite + TypeScript + Tailwind CSS

## 目录结构

```
backend/    FastAPI 后端 API
frontend/   React 前台预约 + 后台管理界面
```

## 本地运行

### 后端

```bash
cd backend
uv venv && uv pip install -e .        # 或 python -m venv .venv && pip install -e .
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8010
```

首次启动会自动建表并写入默认实验室、设备与时间段数据（数据库位于 `backend/data/booking.db`）。

API 文档：http://127.0.0.1:8010/docs

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

后端可通过环境变量覆盖默认配置：

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `ADMIN_USERNAME` | 管理员用户名 | `admin` |
| `ADMIN_PASSWORD` | 管理员密码 | `admin123` |
| `SECRET_KEY` | 令牌签名密钥 | 内置开发密钥 |
| `BOOKING_WINDOW_DAYS` | 可提前预约天数 | `7` |
