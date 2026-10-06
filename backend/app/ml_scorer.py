from __future__ import annotations

import json
import logging
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

import joblib
import numpy as np
from sqlalchemy.orm import Session

from app.config import settings
from app.ml_features import (
    FEATURE_VERSION,
    SYNTHETIC_UID,
    TripContext,
    feature_vector,
    synthetic_weight,
)
from app.models import CatalogItem, GeneratedList, ListItemEvent
from app.schemas import RecommendRequest, WeatherOut

log = logging.getLogger(__name__)

ARTIFACT = Path(__file__).resolve().parent.parent / "ml" / "artifacts" / "model.joblib"
STATS_TTL_SECONDS = 120
MIN_SAMPLES = 3


@dataclass
class _Event:
    kept: int
    weight: float
    activities: frozenset[str]
    tags: frozenset[str]


@dataclass
class FeedbackStats:
    """Labeled feedback loaded once and shared by every item in every request."""

    by_item: dict[int, list[_Event]] = field(default_factory=dict)

    @classmethod
    def load(cls, db: Session) -> "FeedbackStats":
        lists = {
            row.id: row
            for row in db.query(
                GeneratedList.id,
                GeneratedList.uid,
                GeneratedList.activities_json,
                GeneratedList.weather_json,
            )
            .filter(GeneratedList.id.in_(db.query(ListItemEvent.list_id).filter(ListItemEvent.kept.isnot(None))))
            .all()
        }
        events = (
            db.query(ListItemEvent.list_id, ListItemEvent.item_id, ListItemEvent.kept)
            .filter(ListItemEvent.kept.isnot(None))
            .all()
        )
        real = sum(1 for e in events if e.list_id in lists and lists[e.list_id].uid != SYNTHETIC_UID)
        syn_w = synthetic_weight(real, settings.synthetic_fade_events)

        meta: dict[int, tuple[frozenset[str], frozenset[str], float]] = {}
        for list_id, row in lists.items():
            try:
                acts = frozenset(a.lower() for a in json.loads(row.activities_json or "[]"))
                tags = frozenset(json.loads(row.weather_json or "{}").get("tags") or [])
            except (ValueError, AttributeError):
                continue
            meta[list_id] = (acts, tags, syn_w if row.uid == SYNTHETIC_UID else 1.0)

        stats = cls()
        for ev in events:
            m = meta.get(ev.list_id)
            if m is None:
                continue
            stats.by_item.setdefault(ev.item_id, []).append(_Event(int(ev.kept), m[2], m[0], m[1]))
        return stats

    @staticmethod
    def _rate(events: list[_Event]) -> float | None:
        if len(events) < MIN_SAMPLES:
            return None
        total = sum(e.weight for e in events)
        return sum(e.kept * e.weight for e in events) / total if total else None

    def overall(self, item_id: int) -> float | None:
        return self._rate(self.by_item.get(item_id, []))

    def similar(self, item_id: int, activities: list[str], tags: list[str]) -> float | None:
        acts = {a.lower() for a in activities}
        tag_set = set(tags)
        matched = [e for e in self.by_item.get(item_id, []) if e.activities & acts and e.tags & tag_set]
        return self._rate(matched)


class MlScorer:
    def __init__(self, artifact: Path = ARTIFACT) -> None:
        self.artifact = artifact
        self.model = None
        self.spec: dict | None = None
        self.metrics: dict = {}
        self._mtime: float | None = None
        self._stats: FeedbackStats | None = None
        self._stats_at = 0.0
        self._lock = threading.Lock()
        self.reload_if_changed()

    def reload_if_changed(self) -> None:
        """Pick up a retrained model without restarting the API."""
        try:
            mtime = self.artifact.stat().st_mtime
        except FileNotFoundError:
            return
        if mtime == self._mtime:
            return
        with self._lock:
            if mtime == self._mtime:
                return
            try:
                payload = joblib.load(self.artifact)
            except Exception as exc:  # half-written file, wrong sklearn version, ...
                log.warning("Could not load model artifact: %s", exc)
                return
            spec = payload.get("spec")
            if not spec or spec.get("version") != FEATURE_VERSION:
                log.warning("Model artifact uses old features; retrain with ml/train.py")
                self.model, self.spec = None, None
            else:
                self.model, self.spec = payload.get("model"), spec
            self.metrics = payload.get("metrics") or {}
            self._mtime = mtime

    @property
    def is_current(self) -> bool:
        return self.model is not None

    def invalidate_stats(self) -> None:
        self._stats = None

    def stats(self, db: Session) -> FeedbackStats:
        if self._stats is None or time.monotonic() - self._stats_at > STATS_TTL_SECONDS:
            self._stats = FeedbackStats.load(db)
            self._stats_at = time.monotonic()
        return self._stats

    def _ml_probs(self, ctx: TripContext, item_ids: list[int]) -> list[float | None]:
        if self.model is None or self.spec is None or not item_ids:
            return [None] * len(item_ids)
        x = np.array([feature_vector(self.spec, ctx, i) for i in item_ids], dtype=float)
        try:
            return [float(p) for p in self.model.predict_proba(x)[:, 1]]
        except Exception as exc:
            log.warning("Model prediction failed: %s", exc)
            return [None] * len(item_ids)

    def confidences(
        self,
        db: Session,
        items: list[tuple[CatalogItem, int]],
        req: RecommendRequest,
        weather: WeatherOut,
    ) -> list[float]:
        """Average of rule priority, similar-trip keep rate, overall keep rate and model probability."""
        self.reload_if_changed()
        stats = self.stats(db)
        ctx = TripContext(
            lat=weather.latitude,
            lon=weather.longitude,
            duration=(req.end_date - req.start_date).days + 1,
            people=req.people,
            avg_temp_c=weather.avg_temp_c,
            precip_probability=weather.precip_probability,
            tags=weather.tags,
            preference=req.preference,
            activities=req.activities,
        )
        probs = self._ml_probs(ctx, [item.id for item, _ in items])
        out = []
        for (item, priority), ml_prob in zip(items, probs):
            parts = [min(0.95, 0.50 + priority / 200.0)]
            for value in (
                stats.similar(item.id, req.activities, weather.tags),
                stats.overall(item.id),
                ml_prob,
            ):
                if value is not None:
                    parts.append(value)
            out.append(round(sum(parts) / len(parts), 3))
        return out


scorer = MlScorer()
