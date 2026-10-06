from __future__ import annotations

import asyncio
import logging
from datetime import date, timedelta

import httpx

from app.config import settings
from app.schemas import WeatherOut

log = logging.getLogger(__name__)

# A day with at least this much rain (enough to need rain gear) counts as rainy in climate estimates.
RAINY_DAY_MM = 2.5


class WeatherError(Exception):
    pass


def weather_tags(avg_temp_c: float, precip_probability: float) -> list[str]:
    tags: list[str] = []
    if precip_probability >= 60:
        tags.append("rain")
    if avg_temp_c < 18:
        tags.append("cold")
    elif avg_temp_c > 28:
        tags.append("hot")
    else:
        tags.append("normal")
    return tags


def needs_climate(start: date, end: date, today: date | None = None) -> bool:
    """Open-Meteo only forecasts ~16 days ahead; later trips use past years instead."""
    today = today or date.today()
    return end > today + timedelta(days=settings.forecast_horizon_days)


def _shift_year(day: date, years: int) -> date:
    try:
        return day.replace(year=day.year - years)
    except ValueError:  # 29 Feb in a non-leap year
        return day.replace(year=day.year - years, day=28)


def _summary(maxes: list[float], mins: list[float]) -> tuple[float, float, float]:
    max_temp = max(maxes)
    min_temp = min(mins) if mins else max_temp
    avg_temp = (sum(maxes) + sum(mins or maxes)) / (len(maxes) + len(mins or maxes))
    return avg_temp, min_temp, max_temp


async def _geocode(client: httpx.AsyncClient, destination: str) -> tuple[float, float, str]:
    geo = await client.get(
        settings.open_meteo_geocode,
        params={"name": destination, "count": 1, "language": "en", "format": "json"},
    )
    geo.raise_for_status()
    results = geo.json().get("results") or []
    if not results:
        raise WeatherError(f"Could not find the destination \"{destination}\". Check the spelling.")
    place = results[0]
    label = ", ".join(
        part for part in [place.get("name"), place.get("admin1"), place.get("country")] if part
    )
    return place["latitude"], place["longitude"], label


async def _forecast(
    client: httpx.AsyncClient, lat: float, lon: float, start: date, end: date
) -> tuple[float, float, float, float]:
    res = await client.get(
        f"{settings.open_meteo_base}/forecast",
        params={
            "latitude": lat,
            "longitude": lon,
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "timezone": "auto",
        },
    )
    res.raise_for_status()
    daily = res.json().get("daily") or {}
    maxes = [v for v in daily.get("temperature_2m_max") or [] if v is not None]
    mins = [v for v in daily.get("temperature_2m_min") or [] if v is not None]
    rains = [v for v in daily.get("precipitation_probability_max") or [] if v is not None]
    if not maxes:
        raise WeatherError("Weather API returned no daily forecast")
    avg_temp, min_temp, max_temp = _summary(maxes, mins)
    precip = float(max(rains)) if rains else 0.0
    return avg_temp, min_temp, max_temp, precip


async def _climate_year(
    client: httpx.AsyncClient, lat: float, lon: float, start: date, end: date, years_back: int
) -> dict:
    res = await client.get(
        settings.open_meteo_archive,
        params={
            "latitude": lat,
            "longitude": lon,
            "start_date": _shift_year(start, years_back).isoformat(),
            "end_date": _shift_year(end, years_back).isoformat(),
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum",
            "timezone": "auto",
        },
    )
    res.raise_for_status()
    return res.json().get("daily") or {}


async def _climate(
    client: httpx.AsyncClient, lat: float, lon: float, start: date, end: date
) -> tuple[float, float, float, float]:
    """Same calendar dates over past years.

    Rain chance per trip day = share of past years where that day was rainy; like the
    forecast, the trip's rain probability is the highest of those daily chances.
    """
    years = await asyncio.gather(
        *[
            _climate_year(client, lat, lon, start, end, back)
            for back in range(1, settings.climate_years + 1)
        ]
    )
    maxes: list[float] = []
    mins: list[float] = []
    rainy: dict[int, list[int]] = {}
    for daily in years:
        maxes += [v for v in daily.get("temperature_2m_max") or [] if v is not None]
        mins += [v for v in daily.get("temperature_2m_min") or [] if v is not None]
        for i, v in enumerate(daily.get("precipitation_sum") or []):
            if v is not None:
                rainy.setdefault(i, []).append(1 if v >= RAINY_DAY_MM else 0)
    if not maxes:
        raise WeatherError("No past weather data for these dates")
    avg_temp, min_temp, max_temp = _summary(maxes, mins)
    precip = max((100.0 * sum(d) / len(d) for d in rainy.values()), default=0.0)
    return avg_temp, min_temp, max_temp, precip


async def fetch_weather(destination: str, start: date, end: date) -> WeatherOut:
    async with httpx.AsyncClient(timeout=20) as client:
        lat, lon, label = await _geocode(client, destination)

        source = "climate" if needs_climate(start, end) else "forecast"
        if source == "forecast":
            try:
                avg_temp, min_temp, max_temp, precip = await _forecast(client, lat, lon, start, end)
            except (httpx.HTTPError, WeatherError) as exc:
                log.warning("Forecast failed (%s); using climate estimate", exc)
                source = "climate"
        if source == "climate":
            avg_temp, min_temp, max_temp, precip = await _climate(client, lat, lon, start, end)

    return WeatherOut(
        latitude=lat,
        longitude=lon,
        place_name=label,
        avg_temp_c=round(avg_temp, 1),
        min_temp_c=round(min_temp, 1),
        max_temp_c=round(max_temp, 1),
        precip_probability=round(float(precip), 1),
        tags=weather_tags(avg_temp, precip),
        source=source,
    )
