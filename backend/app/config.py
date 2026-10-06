from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_JWT_SECRET = "dev-only-change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./packup.db"
    # local: email/password accounts stored in the API database (JWT bearer tokens)
    # firebase: Firebase ID tokens verified with firebase-admin
    # header: trust the X-User-Id header (tests / local experiments only)
    auth_mode: str = "local"
    jwt_secret: str = DEV_JWT_SECRET
    jwt_expire_days: int = 30
    firebase_project_id: str = ""
    google_application_credentials: str = ""
    open_meteo_base: str = "https://api.open-meteo.com/v1"
    open_meteo_geocode: str = "https://geocoding-api.open-meteo.com/v1/search"
    open_meteo_archive: str = "https://archive-api.open-meteo.com/v1/archive"
    forecast_horizon_days: int = 15
    climate_years: int = 5
    cors_origins: str = "*"
    # Background retraining; 0 disables it.
    retrain_interval_hours: float = 24
    # Synthetic rows fade out as real feedback grows past this many labeled events.
    synthetic_fade_events: int = 300
    admin_token: str = ""


settings = Settings()
