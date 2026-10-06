import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_uid
from app.config import settings
from app.db import get_db
from app.models import User
from app.schemas import AuthResponse, Credentials, PreferenceIn, UserOut
from app.security import create_token, hash_password, verify_password

router = APIRouter(prefix="/v1", tags=["auth"])


def _local_only() -> None:
    if settings.auth_mode != "local":
        raise HTTPException(status_code=404, detail="Email/password accounts are disabled on this server")


def _out(user: User) -> UserOut:
    return UserOut(uid=user.id, email=user.email, preference=user.preference)


@router.post("/auth/register", response_model=AuthResponse, status_code=201)
def register(payload: Credentials, db: Session = Depends(get_db)):
    _local_only()
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(status_code=409, detail="An account with this email already exists. Sign in instead.")
    user = User(id=str(uuid.uuid4()), email=payload.email, password_hash=hash_password(payload.password))
    db.add(user)
    db.commit()
    return AuthResponse(token=create_token(user.id), user=_out(user))


@router.post("/auth/login", response_model=AuthResponse)
def login(payload: Credentials, db: Session = Depends(get_db)):
    _local_only()
    user = db.query(User).filter(User.email == payload.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="No account found for this email. Register first.")
    if not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Wrong password.")
    return AuthResponse(token=create_token(user.id), user=_out(user))


def _get_or_create_user(db: Session, uid: str) -> User:
    user = db.get(User, uid)
    if user:
        return user
    if settings.auth_mode == "local":
        raise HTTPException(status_code=401, detail="Account no longer exists. Please sign in again.")
    # Firebase / header users have no local password; keep a profile row for preferences.
    user = User(id=uid, email=f"{uid}@external", password_hash="!")
    db.add(user)
    db.commit()
    return user


@router.get("/me", response_model=UserOut)
def me(db: Session = Depends(get_db), uid: str = Depends(get_current_uid)):
    return _out(_get_or_create_user(db, uid))


@router.put("/me/preference", response_model=UserOut)
def set_preference(
    payload: PreferenceIn,
    db: Session = Depends(get_db),
    uid: str = Depends(get_current_uid),
):
    user = _get_or_create_user(db, uid)
    user.preference = payload.preference
    db.commit()
    return _out(user)
