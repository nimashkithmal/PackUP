from datetime import date
from typing import Any

from pydantic import BaseModel, Field, field_validator

PREFERENCES = ("minimal", "normal", "prepared")
STATUSES = ("pending", "packed", "need_to_buy", "not_required")


class RecommendRequest(BaseModel):
    trip_id: str
    destination: str = Field(min_length=1, max_length=128)
    start_date: date
    end_date: date
    people: int = Field(ge=1, le=20)
    activities: list[str]
    preference: str = "normal"


class PackingItemOut(BaseModel):
    item_id: int
    slug: str
    name: str
    category: str
    quantity: int
    sources: list[str]
    confidence: float
    suggested: bool = False
    is_safety: bool = False


class WeatherOut(BaseModel):
    latitude: float
    longitude: float
    place_name: str
    avg_temp_c: float
    min_temp_c: float
    max_temp_c: float
    precip_probability: float
    tags: list[str]
    # "forecast" = live forecast, "climate" = estimated from the same dates in past years
    source: str = "forecast"


class RecommendResponse(BaseModel):
    list_id: int
    trip_id: str
    weather: WeatherOut
    items: list[PackingItemOut]


class FeedbackItem(BaseModel):
    item_id: int
    status: str

    @field_validator("status")
    @classmethod
    def _known_status(cls, value: str) -> str:
        if value not in STATUSES:
            raise ValueError(f"status must be one of {', '.join(STATUSES)}")
        return value


class FeedbackRequest(BaseModel):
    items: list[FeedbackItem]
    rating: int | None = Field(default=None, ge=1, le=5)


class Credentials(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=6, max_length=128)

    @field_validator("email")
    @classmethod
    def _email(cls, value: str) -> str:
        value = value.strip().lower()
        local, _, domain = value.partition("@")
        if not local or "." not in domain or " " in value:
            raise ValueError("Enter a valid email address")
        return value


class UserOut(BaseModel):
    uid: str
    email: str
    preference: str


class AuthResponse(BaseModel):
    token: str
    user: UserOut


class PreferenceIn(BaseModel):
    preference: str

    @field_validator("preference")
    @classmethod
    def _known(cls, value: str) -> str:
        if value not in PREFERENCES:
            raise ValueError(f"preference must be one of {', '.join(PREFERENCES)}")
        return value


class TripIn(BaseModel):
    """The app's trip document; items and weather are stored as the app sends them."""

    id: str = Field(min_length=1, max_length=64)
    destination: str = Field(min_length=1, max_length=128)
    start_date: date
    end_date: date
    people: int = Field(ge=1, le=20)
    activities: list[str]
    preference: str = "normal"
    status: str = "draft"
    rating: int | None = Field(default=None, ge=1, le=5)
    list_id: int | None = None
    weather: dict[str, Any] | None = None
    items: list[dict[str, Any]] = Field(default_factory=list)

    @field_validator("start_date", "end_date", mode="before")
    @classmethod
    def _date_only(cls, value: Any) -> Any:
        # The app sends full ISO timestamps; keep the date part.
        if isinstance(value, str) and "T" in value:
            return value.split("T", 1)[0]
        return value


class TripOut(TripIn):
    pass
