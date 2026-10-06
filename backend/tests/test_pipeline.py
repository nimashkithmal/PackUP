from datetime import date, timedelta
from unittest.mock import AsyncMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.schemas import WeatherOut

FAKE_WEATHER = WeatherOut(
    latitude=6.86,
    longitude=81.04,
    place_name="Ella, Uva, Sri Lanka",
    avg_temp_c=24.0,
    min_temp_c=20.0,
    max_temp_c=27.0,
    precip_probability=75.0,
    tags=["rain", "normal"],
)


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def _auth(client, email="hiker@example.com", password="secret123"):
    res = client.post("/v1/auth/register", json={"email": email, "password": password})
    if res.status_code == 409:
        res = client.post("/v1/auth/login", json={"email": email, "password": password})
    assert res.status_code in (200, 201), res.text
    return {"Authorization": f"Bearer {res.json()['token']}"}


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json()["status"] == "ok"


def test_register_login_rules(client):
    res = client.post("/v1/auth/register", json={"email": "New@Example.com ", "password": "secret123"})
    assert res.status_code == 201
    assert res.json()["user"]["email"] == "new@example.com"

    dup = client.post("/v1/auth/register", json={"email": "new@example.com", "password": "other123"})
    assert dup.status_code == 409
    wrong = client.post("/v1/auth/login", json={"email": "new@example.com", "password": "nope1234"})
    assert wrong.status_code == 401
    missing = client.post("/v1/auth/login", json={"email": "ghost@example.com", "password": "secret123"})
    assert missing.status_code == 404
    bad_email = client.post("/v1/auth/register", json={"email": "not-an-email", "password": "secret123"})
    assert bad_email.status_code == 422
    short = client.post("/v1/auth/register", json={"email": "a@b.co", "password": "123"})
    assert short.status_code == 422

    ok = client.post("/v1/auth/login", json={"email": "NEW@example.com", "password": "secret123"})
    assert ok.status_code == 200
    me = client.get("/v1/me", headers={"Authorization": f"Bearer {ok.json()['token']}"})
    assert me.json()["email"] == "new@example.com"


def test_requires_token(client):
    assert client.get("/v1/trips").status_code == 401
    assert client.get("/v1/trips", headers={"Authorization": "Bearer junk"}).status_code == 401


def test_preference_saved(client):
    headers = _auth(client, "pref@example.com")
    res = client.put("/v1/me/preference", headers=headers, json={"preference": "minimal"})
    assert res.status_code == 200
    assert client.get("/v1/me", headers=headers).json()["preference"] == "minimal"
    bad = client.put("/v1/me/preference", headers=headers, json={"preference": "huge"})
    assert bad.status_code == 422


def test_trips_crud_and_isolation(client):
    alice = _auth(client, "alice@example.com")
    bob = _auth(client, "bob@example.com")
    trip = {
        "id": "trip-a1",
        "destination": "Galle",
        "start_date": "2026-11-01T00:00:00.000",
        "end_date": "2026-11-03",
        "people": 2,
        "activities": ["beach"],
        "preference": "normal",
        "items": [{"item_id": -1, "name": "Kite", "status": "pending"}],
    }
    assert client.put("/v1/trips/trip-a1", headers=alice, json=trip).status_code == 200
    listed = client.get("/v1/trips", headers=alice).json()
    assert [t["id"] for t in listed] == ["trip-a1"]
    assert listed[0]["items"][0]["name"] == "Kite"
    assert listed[0]["start_date"] == "2026-11-01"

    assert client.get("/v1/trips", headers=bob).json() == []
    assert client.put("/v1/trips/trip-a1", headers=bob, json=trip).status_code == 404
    assert client.delete("/v1/trips/trip-a1", headers=bob).status_code == 404

    assert client.delete("/v1/trips/trip-a1", headers=alice).status_code == 204
    assert client.get("/v1/trips", headers=alice).json() == []


@patch("app.routers.recommendations.fetch_weather", new_callable=AsyncMock)
def test_hiking_rain_recommendations_and_feedback(mock_weather, client):
    mock_weather.return_value = FAKE_WEATHER
    headers = _auth(client)
    res = client.post(
        "/v1/recommendations",
        headers=headers,
        json={
            "trip_id": "trip-ella-1",
            "destination": "Ella",
            "start_date": date.today().isoformat(),
            "end_date": date.today().isoformat(),
            "people": 2,
            "activities": ["hiking", "sightseeing"],
            "preference": "minimal",
        },
    )
    assert res.status_code == 200, res.text
    data = res.json()
    slugs = {item["slug"] for item in data["items"]}
    assert {"hiking_shoes", "water_bottle", "first_aid", "raincoat", "umbrella"} <= slugs
    tshirts = next(i for i in data["items"] if i["slug"] == "tshirt")
    assert tshirts["quantity"] >= 1
    assert all(0 < i["confidence"] <= 1 for i in data["items"])
    assert data["weather"]["precip_probability"] == 75.0

    umbrella = next(i["item_id"] for i in data["items"] if i["slug"] == "umbrella")
    feedback = client.post(
        "/v1/trips/trip-ella-1/feedback",
        headers=headers,
        json={
            "rating": 5,
            "items": [
                {"item_id": tshirts["item_id"], "status": "packed"},
                {"item_id": umbrella, "status": "not_required"},
                {"item_id": -7, "status": "packed"},  # custom item: ignored
            ],
        },
    )
    assert feedback.status_code == 200, feedback.text
    assert feedback.json()["updated"] == 2
    assert feedback.json()["rating"] == 5

    from app.db import SessionLocal
    from app.models import GeneratedList

    db = SessionLocal()
    try:
        row = db.query(GeneratedList).filter(GeneratedList.trip_id == "trip-ella-1").one()
        assert row.rating == 5
    finally:
        db.close()

    bad = client.post(
        "/v1/trips/trip-ella-1/feedback",
        headers=headers,
        json={"items": [{"item_id": umbrella, "status": "lost"}]},
    )
    assert bad.status_code == 422


def test_activities_endpoint(client):
    acts = client.get("/v1/activities").json()
    assert {"hiking", "beach", "camping", "business", "temple"} <= set(acts)


def test_admin_requires_token(client):
    assert client.get("/v1/admin/model").status_code == 403
    assert client.get("/v1/admin/model", headers={"X-Admin-Token": "test-admin"}).status_code == 200
