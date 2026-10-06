from __future__ import annotations

import json
import random
import sys
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import accuracy_score, roc_auc_score
from sklearn.model_selection import train_test_split
from sqlalchemy.orm import Session

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.config import settings  # noqa: E402
from app.db import SessionLocal, engine  # noqa: E402
from app.migrate import migrate  # noqa: E402
from app.ml_features import (  # noqa: E402
    FEATURE_VERSION,
    KNOWN_COORDS,
    SYNTHETIC_UID,
    build_spec,
    context_from_list,
    feature_vector,
    synthetic_weight,
)
from app.ml_scorer import ARTIFACT  # noqa: E402
from app.models import ActivityRule, CatalogItem, GeneratedList, ListItemEvent, MlModel  # noqa: E402
from app.rules import collect_candidates  # noqa: E402
from app.schemas import WeatherOut  # noqa: E402
from app.seed import seed_if_empty  # noqa: E402
from app.weather import weather_tags  # noqa: E402

SYNTHETIC_PREFIX = "syn2-"
DESTINATIONS = ["Ella", "Galle", "Nuwara Eliya", "Mirissa", "Sigiriya", "Kandy", "Colombo"]
PREFS = ["minimal", "normal", "prepared"]


class NotEnoughData(Exception):
    pass


def _likely_keep(slug: str, activities: list[str], tags: list[str]) -> float:
    p = 0.55
    if slug in {"id_card", "first_aid", "personal_meds", "phone_charger", "tickets"}:
        p = 0.97
    if "hiking" in activities and slug in {"hiking_shoes", "water_bottle", "daypack"}:
        p = 0.95
    if "rain" in tags and slug in {"raincoat", "umbrella"}:
        p = 0.9 if slug == "raincoat" else 0.72
    if "beach" in activities and slug in {"swimwear", "towel", "sunscreen"}:
        p = 0.93
    if "cold" in tags and slug in {"jacket", "sweater"}:
        p = 0.9
    if "camping" in activities and slug in {"tent", "sleeping_bag", "flashlight"}:
        p = 0.94
    if "business" in activities and slug in {"formal_outfit", "laptop"}:
        p = 0.95
    if "temple" in activities and slug in {"white_clothes", "slippers"}:
        p = 0.92
    if slug == "camera":
        p = 0.45
    if slug == "sneakers" and "hiking" in activities:
        p = 0.35
    return p


def seed_synthetic(db: Session, n_trips: int = 150) -> None:
    """Fake trips so confidence works before real users exist. Real feedback outweighs them later."""
    if db.query(GeneratedList).filter(GeneratedList.trip_id.like(f"{SYNTHETIC_PREFIX}%")).count() >= 50:
        return
    # Drop synthetic rows from older versions (no coordinates, fewer activities).
    old_ids = [
        r[0]
        for r in db.query(GeneratedList.id).filter(
            GeneratedList.uid == SYNTHETIC_UID, ~GeneratedList.trip_id.like(f"{SYNTHETIC_PREFIX}%")
        )
    ]
    if old_ids:
        db.query(ListItemEvent).filter(ListItemEvent.list_id.in_(old_ids)).delete(synchronize_session=False)
        db.query(GeneratedList).filter(GeneratedList.id.in_(old_ids)).delete(synchronize_session=False)

    items = db.query(CatalogItem).all()
    activities = sorted({r[0] for r in db.query(ActivityRule.activity).distinct()})
    if not items or not activities:
        db.commit()
        return

    rng = random.Random(42)
    for i in range(n_trips):
        dest = rng.choice(DESTINATIONS)
        lat, lon = KNOWN_COORDS[dest.lower()]
        duration = rng.randint(2, 6)
        people = rng.randint(1, 4)
        pref = rng.choice(PREFS)
        acts = rng.sample(activities, rng.randint(1, 2))
        avg_temp = rng.choice([14.0, 17.0, 22.0, 25.0, 29.0, 32.0])
        precip = rng.choice([10.0, 30.0, 55.0, 70.0, 90.0])
        tags = weather_tags(avg_temp, precip)
        weather = WeatherOut(
            latitude=lat,
            longitude=lon,
            place_name=dest,
            avg_temp_c=avg_temp,
            min_temp_c=avg_temp - 4,
            max_temp_c=avg_temp + 4,
            precip_probability=precip,
            tags=tags,
            source="synthetic",
        )
        lst = GeneratedList(
            trip_id=f"{SYNTHETIC_PREFIX}{i}",
            uid=SYNTHETIC_UID,
            destination=dest,
            duration=duration,
            people=people,
            activities_json=json.dumps(acts),
            weather_json=weather.model_dump_json(),
            preference=pref,
        )
        db.add(lst)
        db.flush()
        # What the rules would recommend, plus a few unrelated items the user might add.
        chosen = {c.item.id: c.item for c in collect_candidates(db, acts, weather).values()}
        for extra in rng.sample(items, k=3):
            chosen.setdefault(extra.id, extra)
        for item in chosen.values():
            keep = rng.random() < _likely_keep(item.slug, acts, tags)
            db.add(
                ListItemEvent(
                    list_id=lst.id,
                    item_id=item.id,
                    recommended=True,
                    final_status="packed" if keep else "not_required",
                    kept=1 if keep else 0,
                    confidence=0.7,
                )
            )
    db.commit()


def load_xyw(db: Session, spec: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray, int]:
    rows = (
        db.query(ListItemEvent, GeneratedList)
        .join(GeneratedList, ListItemEvent.list_id == GeneratedList.id)
        .filter(ListItemEvent.kept.isnot(None))
        .all()
    )
    real = sum(1 for _event, lst in rows if lst.uid != SYNTHETIC_UID)
    syn_w = synthetic_weight(real, settings.synthetic_fade_events)
    contexts: dict[int, object] = {}
    X, y, w = [], [], []
    for event, lst in rows:
        ctx = contexts.get(lst.id)
        if ctx is None:
            ctx = contexts[lst.id] = context_from_list(lst)
        X.append(feature_vector(spec, ctx, event.item_id))
        y.append(int(event.kept))
        w.append(syn_w if lst.uid == SYNTHETIC_UID else 1.0)
    return np.array(X, dtype=float), np.array(y, dtype=int), np.array(w, dtype=float), real


def last_trained_samples(db: Session) -> int | None:
    row = db.query(MlModel).order_by(MlModel.id.desc()).first()
    if not row:
        return None
    try:
        return int(json.loads(row.metrics_json).get("n_samples"))
    except (TypeError, ValueError):
        return None


def train(db: Session, *, only_if_new_data: bool = False) -> dict | None:
    seed_if_empty(db)
    seed_synthetic(db)
    spec = build_spec(db)
    X, y, w, real = load_xyw(db, spec)
    if len(y) < 40 or len(set(y)) < 2:
        raise NotEnoughData("Not enough labeled events to train")
    if only_if_new_data and ARTIFACT.exists() and last_trained_samples(db) == len(y):
        return None

    X_train, X_test, y_train, y_test, w_train, w_test = train_test_split(
        X, y, w, test_size=0.25, random_state=42, stratify=y
    )
    model = GradientBoostingClassifier(random_state=42)
    model.fit(X_train, y_train, sample_weight=w_train)
    proba = model.predict_proba(X_test)[:, 1]
    preds = (proba >= 0.5).astype(int)
    metrics = {
        "accuracy": round(float(accuracy_score(y_test, preds, sample_weight=w_test)), 4),
        "auc": round(float(roc_auc_score(y_test, proba, sample_weight=w_test)), 4),
        "n_samples": int(len(y)),
        "real_samples": real,
        "synthetic_weight": round(synthetic_weight(real, settings.synthetic_fade_events), 3),
        "n_features": int(X.shape[1]),
        "trained_at": datetime.now(timezone.utc).isoformat(),
    }
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    tmp = ARTIFACT.with_suffix(".tmp")
    joblib.dump({"model": model, "spec": spec, "metrics": metrics}, tmp)
    tmp.replace(ARTIFACT)  # atomic, so the API never loads a half-written file
    db.add(
        MlModel(
            version=f"gbc-v{FEATURE_VERSION}",
            metrics_json=json.dumps(metrics),
            artifact_path=str(ARTIFACT),
        )
    )
    db.commit()
    return metrics


def main() -> None:
    migrate(engine)
    db = SessionLocal()
    try:
        try:
            metrics = train(db)
        except NotEnoughData as exc:
            raise SystemExit(str(exc)) from exc
        print(json.dumps(metrics, indent=2))
        print(f"Saved {ARTIFACT}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
