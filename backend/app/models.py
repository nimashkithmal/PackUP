from datetime import date, datetime, timezone

from sqlalchemy import Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    preference: Mapped[str] = mapped_column(String(32), default="normal")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class CatalogItem(Base):
    __tablename__ = "catalog_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    slug: Mapped[str] = mapped_column(String(64), unique=True)
    name: Mapped[str] = mapped_column(String(128))
    category: Mapped[str] = mapped_column(String(32))
    qty_mode: Mapped[str] = mapped_column(String(32))
    base_per_day: Mapped[float] = mapped_column(Float, default=1.0)
    is_safety: Mapped[bool] = mapped_column(Boolean, default=False)

    activity_rules: Mapped[list["ActivityRule"]] = relationship(back_populates="item")
    weather_rules: Mapped[list["WeatherRule"]] = relationship(back_populates="item")


class ActivityRule(Base):
    __tablename__ = "activity_rules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    activity: Mapped[str] = mapped_column(String(64), index=True)
    item_id: Mapped[int] = mapped_column(ForeignKey("catalog_items.id"))
    priority: Mapped[int] = mapped_column(Integer, default=70)

    item: Mapped[CatalogItem] = relationship(back_populates="activity_rules")


class WeatherRule(Base):
    __tablename__ = "weather_rules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    condition_tag: Mapped[str] = mapped_column(String(32), index=True)
    item_id: Mapped[int] = mapped_column(ForeignKey("catalog_items.id"))
    min_precip_prob: Mapped[float | None] = mapped_column(Float, nullable=True)
    max_temp_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    min_temp_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    priority: Mapped[int] = mapped_column(Integer, default=75)

    item: Mapped[CatalogItem] = relationship(back_populates="weather_rules")


class DurationRule(Base):
    __tablename__ = "duration_rules"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    item_id: Mapped[int] = mapped_column(ForeignKey("catalog_items.id"))
    extra_buffer: Mapped[float] = mapped_column(Float, default=0)

    item: Mapped[CatalogItem] = relationship()


class GeneratedList(Base):
    __tablename__ = "generated_lists"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    trip_id: Mapped[str] = mapped_column(String(64), index=True)
    uid: Mapped[str] = mapped_column(String(128), index=True)
    destination: Mapped[str] = mapped_column(String(128))
    duration: Mapped[int] = mapped_column(Integer)
    people: Mapped[int] = mapped_column(Integer)
    activities_json: Mapped[str] = mapped_column(Text)
    weather_json: Mapped[str] = mapped_column(Text)
    preference: Mapped[str] = mapped_column(String(32))
    rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    events: Mapped[list["ListItemEvent"]] = relationship(back_populates="generated_list")


class ListItemEvent(Base):
    __tablename__ = "list_item_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    list_id: Mapped[int] = mapped_column(ForeignKey("generated_lists.id"), index=True)
    item_id: Mapped[int] = mapped_column(ForeignKey("catalog_items.id"), index=True)
    recommended: Mapped[bool] = mapped_column(Boolean, default=True)
    final_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
    kept: Mapped[int | None] = mapped_column(Integer, nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)

    generated_list: Mapped[GeneratedList] = relationship(back_populates="events")
    item: Mapped[CatalogItem] = relationship()


class Trip(Base):
    """A user's trip as the app sees it (items include custom ones and their statuses)."""

    __tablename__ = "trips"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    uid: Mapped[str] = mapped_column(String(128), index=True)
    destination: Mapped[str] = mapped_column(String(128))
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    people: Mapped[int] = mapped_column(Integer)
    activities_json: Mapped[str] = mapped_column(Text)
    preference: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(32), default="draft")
    rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    list_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    weather_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    items_json: Mapped[str] = mapped_column(Text, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)


class MlModel(Base):
    __tablename__ = "ml_models"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    version: Mapped[str] = mapped_column(String(32))
    metrics_json: Mapped[str] = mapped_column(Text)
    artifact_path: Mapped[str] = mapped_column(String(255))
    trained_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
