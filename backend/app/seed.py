from sqlalchemy.orm import Session

from app.models import ActivityRule, CatalogItem, DurationRule, WeatherRule

ITEMS = [
    ("tshirt", "T-shirt", "clothing", "per_day_per_person", 1.0, False),
    ("underwear", "Underwear", "clothing", "per_day_per_person", 1.2, False),
    ("socks", "Socks", "clothing", "per_day_per_person", 1.0, False),
    ("pants", "Pants / trousers", "clothing", "per_person", 1.0, False),
    ("jacket", "Jacket", "clothing", "per_person", 1.0, False),
    ("sweater", "Sweater", "clothing", "per_person", 1.0, False),
    ("raincoat", "Raincoat", "clothing", "per_person", 1.0, False),
    ("swimwear", "Swimwear", "clothing", "per_person", 1.0, False),
    ("hiking_shoes", "Hiking shoes", "footwear", "per_person", 1.0, False),
    ("sandals", "Sandals", "footwear", "per_person", 1.0, False),
    ("sneakers", "Sneakers", "footwear", "per_person", 1.0, False),
    ("toothbrush", "Toothbrush", "personal", "per_person", 1.0, False),
    ("toothpaste", "Toothpaste", "personal", "per_group", 1.0, False),
    ("towel", "Towel", "personal", "per_person", 1.0, False),
    ("sunscreen", "Sunscreen", "personal", "per_group", 1.0, False),
    ("insect_repellent", "Insect repellent", "personal", "per_group", 1.0, False),
    ("first_aid", "First aid kit", "health", "per_group", 1.0, True),
    ("personal_meds", "Personal medication", "health", "per_person", 1.0, True),
    ("phone_charger", "Phone charger", "electronics", "per_person", 1.0, False),
    ("power_bank", "Power bank", "electronics", "per_person", 1.0, False),
    ("id_card", "National ID / passport", "documents", "per_person", 1.0, True),
    ("tickets", "Tickets / bookings", "documents", "per_group", 1.0, True),
    ("snacks", "Snacks", "food", "per_day_per_person", 1.0, False),
    ("water_bottle", "Water bottle", "food", "per_person", 1.0, False),
    ("umbrella", "Umbrella", "activity", "per_person", 1.0, False),
    ("waterproof_bag", "Waterproof bag", "activity", "per_group", 1.0, False),
    ("daypack", "Daypack", "activity", "per_person", 1.0, False),
    ("camera", "Camera", "electronics", "per_group", 1.0, False),
    ("hat", "Sun hat", "clothing", "per_person", 1.0, False),
    ("sleeping_bag", "Sleeping bag", "activity", "per_person", 1.0, False),
    ("tent", "Tent", "activity", "per_group", 1.0, False),
    ("flashlight", "Flashlight / headlamp", "electronics", "per_person", 1.0, False),
    ("formal_outfit", "Formal outfit", "clothing", "per_person", 1.0, False),
    ("laptop", "Laptop + charger", "electronics", "per_person", 1.0, False),
    ("white_clothes", "White / modest clothing", "clothing", "per_person", 1.0, False),
    ("slippers", "Slip-on footwear", "footwear", "per_person", 1.0, False),
]

ACTIVITY_RULES = [
    ("hiking", "hiking_shoes", 95),
    ("hiking", "water_bottle", 92),
    ("hiking", "first_aid", 90),
    ("hiking", "daypack", 85),
    ("hiking", "snacks", 80),
    ("hiking", "insect_repellent", 70),
    ("sightseeing", "sneakers", 80),
    ("sightseeing", "daypack", 75),
    ("sightseeing", "camera", 70),
    ("sightseeing", "hat", 65),
    ("beach", "swimwear", 95),
    ("beach", "towel", 90),
    ("beach", "sunscreen", 92),
    ("beach", "sandals", 85),
    ("beach", "hat", 80),
    ("camping", "tent", 95),
    ("camping", "sleeping_bag", 93),
    ("camping", "flashlight", 90),
    ("camping", "insect_repellent", 85),
    ("camping", "water_bottle", 85),
    ("camping", "first_aid", 88),
    ("business", "formal_outfit", 92),
    ("business", "laptop", 90),
    ("business", "power_bank", 70),
    ("temple", "white_clothes", 92),
    ("temple", "slippers", 80),
    ("temple", "hat", 60),
]

WEATHER_RULES = [
    ("rain", "umbrella", 60, None, None, 88),
    ("rain", "raincoat", 60, None, None, 90),
    ("rain", "waterproof_bag", 60, None, None, 78),
    ("cold", "jacket", None, 18, None, 90),
    ("cold", "sweater", None, 18, None, 85),
    ("hot", "sunscreen", None, None, 28, 88),
    ("hot", "hat", None, None, 28, 80),
    ("hot", "water_bottle", None, None, 28, 85),
]

ESSENTIALS = [
    ("toothbrush", 60),
    ("toothpaste", 60),
    ("phone_charger", 70),
    ("id_card", 99),
    ("tickets", 90),
    ("personal_meds", 80),
    ("first_aid", 75),
    ("tshirt", 70),
    ("underwear", 70),
    ("socks", 70),
    ("pants", 65),
    ("sneakers", 55),
]

DURATION_ITEMS = ["tshirt", "underwear", "socks", "snacks"]


def seed_if_empty(db: Session) -> None:
    """Insert any catalog items / rules that are missing, so new seed rows reach old databases."""
    by_slug: dict[str, CatalogItem] = {row.slug: row for row in db.query(CatalogItem).all()}
    for slug, name, category, qty_mode, base, safety in ITEMS:
        if slug in by_slug:
            continue
        item = CatalogItem(
            slug=slug,
            name=name,
            category=category,
            qty_mode=qty_mode,
            base_per_day=base,
            is_safety=safety,
        )
        db.add(item)
        db.flush()
        by_slug[slug] = item

    have_activity = {(r.activity, r.item_id) for r in db.query(ActivityRule).all()}
    for activity, slug, priority in ACTIVITY_RULES:
        if (activity, by_slug[slug].id) not in have_activity:
            db.add(ActivityRule(activity=activity, item_id=by_slug[slug].id, priority=priority))

    have_weather = {(r.condition_tag, r.item_id) for r in db.query(WeatherRule).all()}
    for tag, slug, min_p, max_t, min_t, priority in WEATHER_RULES:
        if (tag, by_slug[slug].id) in have_weather:
            continue
        db.add(
            WeatherRule(
                condition_tag=tag,
                item_id=by_slug[slug].id,
                min_precip_prob=min_p,
                max_temp_c=max_t,
                min_temp_c=min_t,
                priority=priority,
            )
        )

    have_duration = {r.item_id for r in db.query(DurationRule).all()}
    for slug in DURATION_ITEMS:
        if by_slug[slug].id in have_duration:
            continue
        extra = 1.0 if slug == "underwear" else 0.0
        db.add(DurationRule(item_id=by_slug[slug].id, extra_buffer=extra))

    db.commit()
