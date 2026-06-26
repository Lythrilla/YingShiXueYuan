import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.getenv("DATA_DIR", BASE_DIR / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)

DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{DATA_DIR / 'booking.db'}")

# 后台管理员账号（可通过环境变量覆盖）
ADMIN_USERNAME = os.getenv("ADMIN_USERNAME", "admin")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "admin123")

# 用于签发后台登录 token 的密钥
SECRET_KEY = os.getenv("SECRET_KEY", "yingshi-recording-lab-secret-key-change-me")
TOKEN_MAX_AGE = int(os.getenv("TOKEN_MAX_AGE", str(60 * 60 * 12)))  # 12 小时
