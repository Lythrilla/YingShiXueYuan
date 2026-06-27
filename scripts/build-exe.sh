#!/usr/bin/env bash
# 一键构建：先打包前端，再把前端嵌入 Rust 后端，交叉编译出单文件 Windows .exe。
#
# 依赖（Linux 交叉编译）：
#   - rustup target add x86_64-pc-windows-gnu
#   - gcc-mingw-w64-x86-64  (提供 x86_64-w64-mingw32-gcc)
#   在 Windows 上本机构建可直接用： cargo build --release
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${TARGET:-x86_64-pc-windows-gnu}"

echo "==> 构建前端 (frontend/dist)"
cd "$ROOT/frontend"
npm install
npm run build

echo "==> 交叉编译 Rust 后端 ($TARGET)"
cd "$ROOT/backend"
cargo build --release --target "$TARGET"

OUT="$ROOT/backend/target/$TARGET/release/yingshi-booking.exe"
DIST="$ROOT/dist"
mkdir -p "$DIST"
cp "$OUT" "$DIST/录音实验室预约系统.exe"

echo ""
echo "==> 完成：$DIST/录音实验室预约系统.exe"
echo "    双击运行后浏览器访问 http://127.0.0.1:8010"
echo "    数据库会自动建在 exe 同级的 data/booking.db"
