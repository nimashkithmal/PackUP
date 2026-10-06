import json

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.auth import get_current_uid
from app.db import get_db
from app.models import Trip
from app.schemas import TripIn, TripOut

router = APIRouter(prefix="/v1", tags=["trips"])


def _out(trip: Trip) -> TripOut:
    return TripOut(
        id=trip.id,
        destination=trip.destination,
        start_date=trip.start_date,
        end_date=trip.end_date,
        people=trip.people,
        activities=json.loads(trip.activities_json),
        preference=trip.preference,
        status=trip.status,
        rating=trip.rating,
        list_id=trip.list_id,
        weather=json.loads(trip.weather_json) if trip.weather_json else None,
        items=json.loads(trip.items_json or "[]"),
    )


@router.get("/trips", response_model=list[TripOut])
def list_trips(db: Session = Depends(get_db), uid: str = Depends(get_current_uid)):
    rows = db.query(Trip).filter(Trip.uid == uid).order_by(Trip.start_date.desc()).all()
    return [_out(t) for t in rows]


@router.put("/trips/{trip_id}", response_model=TripOut)
def save_trip(
    trip_id: str,
    payload: TripIn,
    db: Session = Depends(get_db),
    uid: str = Depends(get_current_uid),
):
    if payload.id != trip_id:
        raise HTTPException(status_code=400, detail="Trip id in body does not match the URL")
    if payload.end_date < payload.start_date:
        raise HTTPException(status_code=400, detail="end_date must be on or after start_date")
    trip = db.get(Trip, trip_id)
    if trip and trip.uid != uid:
        raise HTTPException(status_code=404, detail="Trip not found")
    if not trip:
        trip = Trip(id=trip_id, uid=uid)
        db.add(trip)
    trip.destination = payload.destination
    trip.start_date = payload.start_date
    trip.end_date = payload.end_date
    trip.people = payload.people
    trip.activities_json = json.dumps(payload.activities)
    trip.preference = payload.preference
    trip.status = payload.status
    trip.rating = payload.rating
    trip.list_id = payload.list_id
    trip.weather_json = json.dumps(payload.weather) if payload.weather is not None else None
    trip.items_json = json.dumps(payload.items)
    db.commit()
    return _out(trip)


@router.delete("/trips/{trip_id}", status_code=204)
def delete_trip(trip_id: str, db: Session = Depends(get_db), uid: str = Depends(get_current_uid)):
    trip = db.get(Trip, trip_id)
    if not trip or trip.uid != uid:
        raise HTTPException(status_code=404, detail="Trip not found")
    # Generated lists and their feedback stay: they are anonymous training data.
    db.delete(trip)
    db.commit()
    return Response(status_code=204)
