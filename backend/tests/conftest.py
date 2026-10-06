import os
from pathlib import Path

# Tests use their own SQLite file, never the MySQL database from .env.
_DB = Path(__file__).resolve().parent.parent / "test_packup.db"
if _DB.exists():
    _DB.unlink()
os.environ["DATABASE_URL"] = f"sqlite:///{_DB}"
os.environ["AUTH_MODE"] = "local"
os.environ["JWT_SECRET"] = "test-secret-that-is-long-enough-for-hs256-signing"
os.environ["RETRAIN_INTERVAL_HOURS"] = "0"
os.environ["ADMIN_TOKEN"] = "test-admin"
os.environ["CORS_ORIGINS"] = "http://localhost"
