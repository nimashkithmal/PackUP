from __future__ import annotations

import json

from sqlalchemy.orm import Session

from app.ml_scorer import scorer
from app.models import GeneratedList, ListItemEvent
from app.rules import collect_candidates, quantities_for
from app.schemas import PackingItemOut, RecommendRequest, RecommendResponse, WeatherOut


def generate_list(
    db: Session,
    uid: str,
    req: RecommendRequest,
    weather: WeatherOut,
) -> RecommendResponse:
    duration = (req.end_date - req.start_date).days + 1
    candidates = collect_candidates(db, req.activities, weather)
    qtys = quantities_for(db, candidates, duration, req.people, req.preference)

    ordered = list(candidates.items())
    confs = scorer.confidences(db, [(cand.item, cand.priority) for _, cand in ordered], req, weather)

    items_out: list[PackingItemOut] = []
    for (item_id, cand), conf in zip(ordered, confs):
        suggested = conf < 0.62 and not cand.item.is_safety
        if cand.item.is_safety:
            conf = max(conf, 0.85)
        items_out.append(
            PackingItemOut(
                item_id=cand.item.id,
                slug=cand.item.slug,
                name=cand.item.name,
                category=cand.item.category,
                quantity=qtys[item_id],
                sources=cand.sources,
                confidence=conf,
                suggested=suggested,
                is_safety=cand.item.is_safety,
            )
        )

    category_order = [
        "clothing",
        "footwear",
        "personal",
        "health",
        "electronics",
        "documents",
        "food",
        "activity",
    ]
    items_out.sort(key=lambda x: (category_order.index(x.category) if x.category in category_order else 99, -x.confidence))

    generated = GeneratedList(
        trip_id=req.trip_id,
        uid=uid,
        destination=req.destination,
        duration=duration,
        people=req.people,
        activities_json=json.dumps([a.lower() for a in req.activities]),
        weather_json=weather.model_dump_json(),
        preference=req.preference,
    )
    db.add(generated)
    db.flush()

    for item in items_out:
        db.add(
            ListItemEvent(
                list_id=generated.id,
                item_id=item.item_id,
                recommended=True,
                final_status=None,
                kept=None,
                confidence=item.confidence,
            )
        )
    db.commit()

    return RecommendResponse(list_id=generated.id, trip_id=req.trip_id, weather=weather, items=items_out)
