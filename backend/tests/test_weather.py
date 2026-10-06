from datetime import date, timedelta
from unittest.mock import AsyncMock, patch

import httpx

from app import weather
from app.weather import fetch_weather, needs_climate, weather_tags


def test_needs_climate_after_forecast_horizon():
    today = date(2026, 10, 7)
    assert not needs_climate(today, today + timedelta(days=3), today)
    assert needs_climate(date(2026, 12, 20), date(2026, 12, 23), today)


def test_shift_year_leap_day():
    assert weather._shift_year(date(2028, 2, 29), 1) == date(2027, 2, 28)


def test_tags():
    assert weather_tags(30, 80) == ["rain", "hot"]
    assert weather_tags(15, 10) == ["cold"]


GEO = (6.87, 81.05, "Ella, Uva, Sri Lanka")


@patch.object(weather, "_climate", new_callable=AsyncMock, return_value=(22.0, 15.0, 28.0, 65.0))
@patch.object(weather, "_forecast", new_callable=AsyncMock)
@patch.object(weather, "_geocode", new_callable=AsyncMock, return_value=GEO)
async def _far_trip(geo, forecast, climate):
    start = date.today() + timedelta(days=60)
    out = await fetch_weather("Ella", start, start + timedelta(days=3))
    forecast.assert_not_called()
    return out


def test_far_trip_uses_climate():
    import asyncio

    out = asyncio.run(_far_trip())
    assert out.source == "climate"
    assert out.tags == ["rain", "normal"]


def test_forecast_error_falls_back_to_climate():
    import asyncio

    async def run():
        with patch.object(weather, "_geocode", new_callable=AsyncMock, return_value=GEO), patch.object(
            weather,
            "_forecast",
            new_callable=AsyncMock,
            side_effect=httpx.HTTPStatusError("400", request=httpx.Request("GET", "x"), response=httpx.Response(400)),
        ), patch.object(weather, "_climate", new_callable=AsyncMock, return_value=(25.0, 20.0, 30.0, 20.0)):
            return await fetch_weather("Ella", date.today(), date.today() + timedelta(days=2))

    out = asyncio.run(run())
    assert out.source == "climate"
