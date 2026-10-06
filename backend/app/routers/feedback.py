from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.auth import get_current_uid
from app.db import get_db
from app.ml_scorer import scorer
from app.models import CatalogItem, GeneratedList, ListItemEvent, Trip
from app.schemas import FeedbackRequest

router = APIRouter(prefix="/v1", tags=["feedback"])

KEPT_STATUSES = {"packed", "need_to_buy"}


@router.post("/trips/{trip_id}/feedback")
def save_feedback(
    trip_id: str,
    payload: FeedbackRequest,
    db: Session = Depends(get_db),
    uid: str = Depends(get_current_uid),
):
    generated = (
        db.query(GeneratedList)
        .filter(GeneratedList.trip_id == trip_id, GeneratedList.uid == uid)
        .order_by(GeneratedList.id.desc())
        .first()
    )
    if not generated:
        raise HTTPException(status_code=404, detail="Generated list not found")

    known_ids = {row[0] for row in db.query(CatalogItem.id).all()}
    events = {e.item_id: e for e in generated.events}
    updated = 0
    for item in payload.items:
        if item.item_id not in known_ids:
            continue  # custom items the user typed in are not catalog items
        event = events.get(item.item_id)
        if not event:
            event = ListItemEvent(
                list_id=generated.id,
                item_id=item.item_id,
                recommended=False,
            )
            db.add(event)
            events[item.item_id] = event
        event.final_status = item.status
        if item.status == "pending":
            event.kept = None
        else:
            event.kept = 1 if item.status in KEPT_STATUSES else 0
        updated += 1

    if payload.rating is not None:
        generated.rating = payload.rating
        trip = db.get(Trip, trip_id)
        if trip and trip.uid == uid:
            trip.rating = payload.rating
    db.commit()
    scorer.invalidate_stats()
    return {"ok": True, "updated": updated, "rating": generated.rating}
