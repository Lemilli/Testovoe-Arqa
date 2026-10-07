from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.main import create_app


@pytest.fixture
def client(database_engine: Engine) -> Iterator[TestClient]:
    application = create_app()

    def session_override() -> Iterator[Session]:
        with Session(database_engine, expire_on_commit=False) as session:
            yield session

    application.dependency_overrides[get_session] = session_override
    with TestClient(application) as test_client:
        yield test_client


def make_trip(trip_id: str, **changes: object) -> dict[str, object]:
    return {
        "id": trip_id,
        "start": "2026-10-01T08:10:00+05:00",
        "end": "2026-10-01T08:32:00+05:00",
        "amount": 2400,
        "payment": "card",
        "commission": 360,
    } | changes


def test_control_day_has_summary_and_newest_first(client: TestClient) -> None:
    first = make_trip("t1")
    second = make_trip(
        "t2",
        start="2026-10-01T09:05:00+05:00",
        end="2026-10-01T09:20:00+05:00",
        amount=1500,
        payment="cash",
        commission=225,
    )
    assert client.post("/api/v1/trips", json=second).status_code == 201
    assert client.post("/api/v1/trips", json=first).status_code == 201

    response = client.get("/api/v1/days/2026-10-01")

    assert response.status_code == 200
    assert response.json() == {
        "date": "2026-10-01",
        "trips": [
            second | {"start": "2026-10-01T04:05:00Z", "end": "2026-10-01T04:20:00Z"},
            first | {"start": "2026-10-01T03:10:00Z", "end": "2026-10-01T03:32:00Z"},
        ],
        "summary": {
            "trip_count": 2,
            "revenue": 3900,
            "commission": 585,
            "net_income": 3315,
            "cash": 1500,
            "card": 2400,
        },
    }


def test_empty_day_has_no_trips_and_zero_indicators(client: TestClient) -> None:
    assert client.post("/api/v1/trips", json=make_trip("other-day")).status_code == 201

    response = client.get("/api/v1/days/2026-10-02")

    assert response.status_code == 200
    assert response.json() == {
        "date": "2026-10-02",
        "trips": [],
        "summary": {
            "trip_count": 0,
            "revenue": 0,
            "commission": 0,
            "net_income": 0,
            "cash": 0,
            "card": 0,
        },
    }


def test_midnight_boundaries_and_cross_midnight_follow_almaty(
    client: TestClient,
) -> None:
    trips = [
        make_trip(
            "before",
            start="2026-09-30T23:59:59.999999+05:00",
            end="2026-10-01T00:10:00+05:00",
        ),
        make_trip(
            "midnight",
            start="2026-09-30T19:00:00Z",
            end="2026-09-30T19:10:00Z",
        ),
        make_trip(
            "cross-midnight",
            start="2026-10-01T23:50:00+05:00",
            end="2026-10-02T00:20:00+05:00",
        ),
        make_trip(
            "last-microsecond",
            start="2026-10-01T23:59:59.999999+05:00",
            end="2026-10-02T00:10:00+05:00",
        ),
        make_trip(
            "next-midnight",
            start="2026-10-02T03:00:00+08:00",
            end="2026-10-01T19:10:00Z",
        ),
    ]
    for trip in trips:
        assert client.post("/api/v1/trips", json=trip).status_code == 201

    selected = client.get("/api/v1/days/2026-10-01").json()

    assert [trip["id"] for trip in selected["trips"]] == [
        "last-microsecond",
        "cross-midnight",
        "midnight",
    ]
    assert selected["summary"]["trip_count"] == 3
    assert selected["summary"]["revenue"] == 7200
    assert [
        trip["id"] for trip in client.get("/api/v1/days/2026-09-30").json()["trips"]
    ] == ["before"]
    assert [
        trip["id"] for trip in client.get("/api/v1/days/2026-10-02").json()["trips"]
    ] == ["next-midnight"]


@pytest.mark.parametrize(
    "day",
    [
        "not-a-date",
        "2026-02-30",
        "2026-13-01",
        "2026-10-1",
        "2026-1-01",
        "20261001",
        "1790809800",
        "2026-10-01T00:00:00Z",
        "0001-01-01",
        "9999-12-31",
    ],
)
def test_invalid_date_returns_422(client: TestClient, day: str) -> None:
    response = client.get(f"/api/v1/days/{day}")

    assert response.status_code == 422
    assert isinstance(response.json()["detail"], list)


@pytest.mark.parametrize("payment", ["cash", "card"])
def test_money_preserves_integer_precision_and_summary_can_exceed_db_limit(
    client: TestClient, payment: str
) -> None:
    amount = 2**63 - 1
    for trip_id in ["large-a", "large-b"]:
        response = client.post(
            "/api/v1/trips",
            json=make_trip(trip_id, amount=amount, commission=0, payment=payment),
        )
        assert response.status_code == 201
        assert response.json()["amount"] == amount
        assert type(response.json()["amount"]) is int

    summary = client.get("/api/v1/days/2026-10-01").json()["summary"]

    assert summary == {
        "trip_count": 2,
        "revenue": amount * 2,
        "commission": 0,
        "net_income": amount * 2,
        "cash": amount * 2 if payment == "cash" else 0,
        "card": amount * 2 if payment == "card" else 0,
    }
    assert all(type(value) is int for value in summary.values())


def test_commission_is_money_and_can_exceed_amount(client: TestClient) -> None:
    response = client.post(
        "/api/v1/trips", json=make_trip("loss", amount=100, commission=150)
    )
    assert response.status_code == 201

    summary = client.get("/api/v1/days/2026-10-01").json()["summary"]

    assert summary == {
        "trip_count": 1,
        "revenue": 100,
        "commission": 150,
        "net_income": -50,
        "cash": 0,
        "card": 100,
    }


def test_openapi_documents_day_date_trips_and_integer_summary(
    client: TestClient,
) -> None:
    schema = client.get("/openapi.json").json()
    operation = schema["paths"]["/api/v1/days/{date}"]["get"]
    assert {"200", "422"} <= operation["responses"].keys()
    parameter = next(item for item in operation["parameters"] if item["name"] == "date")
    assert parameter["in"] == "path"
    assert parameter["required"] is True
    reference = operation["responses"]["200"]["content"]["application/json"]["schema"][
        "$ref"
    ]
    response_schema = schema["components"]["schemas"][reference.rsplit("/", 1)[1]]
    assert set(response_schema["required"]) == {"date", "trips", "summary"}
    assert response_schema["properties"]["trips"]["type"] == "array"
    summary_ref = response_schema["properties"]["summary"]["$ref"]
    summary_schema = schema["components"]["schemas"][summary_ref.rsplit("/", 1)[1]]
    assert set(summary_schema["properties"]) == {
        "trip_count",
        "revenue",
        "commission",
        "net_income",
        "cash",
        "card",
    }
    assert all(
        field["type"] == "integer" for field in summary_schema["properties"].values()
    )
