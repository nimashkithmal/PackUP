from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_uid
from app.db import get_db
from app.recommend import generate_list
from app.schemas import RecommendRequest, RecommendResponse
from app.weather import WeatherError, fetch_weather

router = APIRouter(prefix="/v1", tags=["recommendations"])


@router.post("/recommendations", response_model=RecommendResponse)
async def create_recommendation(
    payload: RecommendRequest,
    db: Session = Depends(get_db),
    uid: str = Depends(get_current_uid),
):
    if payload.end_date < payload.start_date:
        raise HTTPException(status_code=400, detail="end_date must be on or after start_date")
    try:
        weather = await fetch_weather(payload.destination, payload.start_date, payload.end_date)
    except WeatherError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Weather service unavailable") from exc
    return generate_list(db, uid, payload, weather)
