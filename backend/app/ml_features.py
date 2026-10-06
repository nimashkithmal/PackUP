"""Feature encoding shared by training (ml/train.py) and scoring (app/ml_scorer.py).

The spec (which activities and catalog items get a one-hot column) is saved inside the
model artifact, so a model keeps working after new activities or items are added: unknown
ones simply get all-zero columns until the next retrain.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

from sqlalchemy.orm import Session

from app.models import ActivityRule, CatalogItem, GeneratedList

FEATURE_VERSION = 2
TAGS = ["rain", "cold", "hot", "normal"]
PREFS = ["minimal", "normal", "prepared"]
SYNTHETIC_UID = "synthetic"

# Coordinates for destinations used by older synthetic rows that stored no lat/lon.
KNOWN_COORDS = {
    "ella": (6.87, 81.05),
    "galle": (6.03, 80.22),
    "nuwara eliya": (6.97, 80.78),
    "mirissa": (5.95, 80.46),
    "sigiriya": (7.96, 80.76),
    "kandy": (7.29, 80.63),
    "colombo": (6.93, 79.86),
}


@dataclass
class TripContext:
    lat: float
    lon: float
    duration: int
    people: int
    avg_temp_c: float
    precip_probability: float
    tags: list[str]
    preference: str
    activities: list[str]


def build_spec(db: Session) -> dict:
    activities = sorted({r[0] for r in db.query(ActivityRule.activity).distinct().all()})
    item_ids = sorted(r[0] for r in db.query(CatalogItem.id).all())
    return {"version": FEATURE_VERSION, "activities": activities, "item_ids": item_ids}


def context_from_list(lst: GeneratedList) -> TripContext:
    weather = json.loads(lst.weather_json or "{}")
    tags = weather.get("tags") or []
    lat, lon = weather.get("latitude"), weather.get("longitude")
    if lat is None or lon is None:
        lat, lon = KNOWN_COORDS.get(lst.destination.strip().lower(), (0.0, 0.0))
    avg = weather.get("avg_temp_c")
    if avg is None:
        avg = 16.0 if "cold" in tags else 31.0 if "hot" in tags else 24.0
    precip = weather.get("precip_probability")
    if precip is None:
        precip = 75.0 if "rain" in tags else 20.0
    return TripContext(
        lat=float(lat),
        lon=float(lon),
        duration=lst.duration,
        people=lst.people,
        avg_temp_c=float(avg),
        precip_probability=float(precip),
        tags=list(tags),
        preference=lst.preference,
        activities=json.loads(lst.activities_json or "[]"),
    )


def feature_vector(spec: dict, ctx: TripContext, item_id: int) -> list[float]:
    acts = {a.strip().lower() for a in ctx.activities}
    return [
        ctx.lat,
        ctx.lon,
        float(ctx.duration),
        float(ctx.people),
        ctx.avg_temp_c,
        ctx.precip_probability,
        *[1.0 if t in ctx.tags else 0.0 for t in TAGS],
        *[1.0 if ctx.preference == p else 0.0 for p in PREFS],
        *[1.0 if a in acts else 0.0 for a in spec["activities"]],
        *[1.0 if item_id == i else 0.0 for i in spec["item_ids"]],
    ]


def synthetic_weight(real_events: int, fade_events: int) -> float:
    """Synthetic rows count fully with no real data and fade to 5% as real feedback grows."""
    if fade_events <= 0:
        return 1.0
    return max(0.05, 1.0 - real_events / fade_events)
