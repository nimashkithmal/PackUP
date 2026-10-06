import asyncio
import logging
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import DEV_JWT_SECRET, settings
from app.db import SessionLocal, engine
from app.migrate import migrate
from app.routers import admin, auth, catalog, feedback, recommendations, trips
from app.seed import seed_if_empty
from app.training import retrain_loop
from app import models  # noqa: F401

log = logging.getLogger("packup")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    migrate(engine)
    db = SessionLocal()
    try:
        seed_if_empty(db)
    finally:
        db.close()

    if settings.auth_mode == "local" and settings.jwt_secret == DEV_JWT_SECRET:
        log.warning("JWT_SECRET is the development default. Set a long random JWT_SECRET before deploying.")
    if settings.auth_mode == "header":
        log.warning("AUTH_MODE=header trusts X-User-Id. Never use it on a public server.")
    if settings.cors_origins.strip() == "*":
        log.warning("CORS_ORIGINS=* allows any website. Set your app's origin before deploying.")

    task = None
    if settings.retrain_interval_hours > 0:
        task = asyncio.create_task(retrain_loop())
    yield
    if task:
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task


origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app = FastAPI(title="PackUP Recommendation API", version="1.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    # Auth uses bearer headers, not cookies; credentials with "*" would be rejected by browsers anyway.
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(auth.router)
app.include_router(trips.router)
app.include_router(catalog.router)
app.include_router(recommendations.router)
app.include_router(feedback.router)
app.include_router(admin.router)


@app.get("/health")
def health():
    return {"status": "ok"}
