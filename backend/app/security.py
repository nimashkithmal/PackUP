import base64
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

import jwt

from app.config import settings

_ITERATIONS = 240_000


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _ITERATIONS)
    return "pbkdf2_sha256${}${}${}".format(
        _ITERATIONS,
        base64.b64encode(salt).decode(),
        base64.b64encode(digest).decode(),
    )


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, iterations, salt_b64, digest_b64 = stored.split("$")
    except ValueError:
        return False
    if algo != "pbkdf2_sha256":
        return False
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode(), base64.b64decode(salt_b64), int(iterations)
    )
    return hmac.compare_digest(digest, base64.b64decode(digest_b64))


def create_token(uid: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": uid,
        "iat": now,
        "exp": now + timedelta(days=settings.jwt_expire_days),
        "iss": "packup",
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_token(token: str) -> str | None:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"], issuer="packup")
    except jwt.PyJWTError:
        return None
    sub = payload.get("sub")
    return str(sub) if sub else None
