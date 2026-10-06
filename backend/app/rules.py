from __future__ import annotations

import math
from dataclasses import dataclass, field

from sqlalchemy.orm import Session

from app.models import ActivityRule, CatalogItem, DurationRule, WeatherRule
from app.schemas import WeatherOut
from app.seed import ESSENTIALS

PREFERENCE_FACTOR = {
    "minimal": 0.7,
    "normal": 1.0,
    "prepared": 1.25,
}


@dataclass
class Candidate:
    item: CatalogItem
    sources: list[str] = field(default_factory=list)
    priority: int = 0

    def add_source(self, source: str, priority: int) -> None:
        if source not in self.sources:
            self.sources.append(source)
        self.priority = max(self.priority, priority)


def _quantity(item: CatalogItem, duration: int, people: int, preference: str, extra: float) -> int:
    factor = PREFERENCE_FACTOR.get(preference, 1.0)
    if item.qty_mode == "per_day_per_person":
        raw = item.base_per_day * duration * people * factor + extra * people
        return max(1, math.ceil(raw))
    if item.qty_mode == "per_person":
        raw = people * factor
        return max(1, math.ceil(raw))
    return 1


def collect_candidates(
    db: Session,
    activities: list[str],
    weather: WeatherOut,
) -> dict[int, Candidate]:
    items = {row.id: row for row in db.query(CatalogItem).all()}
    by_slug = {row.slug: row for row in items.values()}
    out: dict[int, Candidate] = {}

    def add(item: CatalogItem, source: str, priority: int) -> None:
        cand = out.setdefault(item.id, Candidate(item=item))
        cand.add_source(source, priority)

    for slug, priority in ESSENTIALS:
        add(by_slug[slug], "rule:essentials", priority)

    normalized = [a.strip().lower() for a in activities]
    if normalized:
        rules = db.query(ActivityRule).filter(ActivityRule.activity.in_(normalized)).all()
        for rule in rules:
            add(items[rule.item_id], f"rule:{rule.activity}", rule.priority)

    weather_rules = db.query(WeatherRule).filter(WeatherRule.condition_tag.in_(weather.tags)).all()
    for rule in weather_rules:
        if rule.min_precip_prob is not None and weather.precip_probability < rule.min_precip_prob:
            continue
        if rule.condition_tag == "cold" and weather.avg_temp_c > (rule.max_temp_c or 18):
            continue
        if rule.condition_tag == "hot" and weather.avg_temp_c < (rule.min_temp_c or 28):
            continue
        add(items[rule.item_id], f"weather:{rule.condition_tag}", rule.priority)

    return out


def quantities_for(
    db: Session,
    candidates: dict[int, Candidate],
    duration: int,
    people: int,
    preference: str,
) -> dict[int, int]:
    extras = {row.item_id: row.extra_buffer for row in db.query(DurationRule).all()}
    return {
        item_id: _quantity(cand.item, duration, people, preference, extras.get(item_id, 0.0))
        for item_id, cand in candidates.items()
    }
