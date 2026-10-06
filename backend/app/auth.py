from fastapi import Depends, Header, HTTPException

from app.config import settings
from app.security import decode_token

_firebase_app = None


def _firebase():
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app
    import firebase_admin
    from firebase_admin import credentials

    options = {"projectId": settings.firebase_project_id} if settings.firebase_project_id else None
    if settings.google_application_credentials:
        cred = credentials.Certificate(settings.google_application_credentials)
        _firebase_app = firebase_admin.initialize_app(cred, options)
    else:
        _firebase_app = firebase_admin.initialize_app(options=options)
    return _firebase_app


def _bearer(authorization: str | None) -> str | None:
    if authorization and authorization.startswith("Bearer "):
        return authorization.split(" ", 1)[1].strip() or None
    return None


def get_current_uid(
    authorization: str | None = Header(default=None),
    x_user_id: str | None = Header(default=None, alias="X-User-Id"),
) -> str:
    if settings.auth_mode == "header":
        return x_user_id or "demo-user"

    token = _bearer(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Missing bearer token")

    if settings.auth_mode == "firebase":
        try:
            from firebase_admin import auth as fb_auth

            _firebase()
            decoded = fb_auth.verify_id_token(token)
            return str(decoded["uid"])
        except Exception as exc:
            raise HTTPException(status_code=401, detail="Invalid or expired Firebase token") from exc

    uid = decode_token(token)
    if not uid:
        raise HTTPException(status_code=401, detail="Session expired. Please sign in again.")
    return uid


CurrentUid = Depends(get_current_uid)
