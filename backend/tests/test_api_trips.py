from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Lock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import Engine, event, func, select
from sqlalchemy.orm import Session

from app.api.dependencies import get_session
from app.db.database import create_database_engine
from app.db.models import Trip
from app.main import create_app

TRIP = {
    "id": "t1",
    "start": "2026-10-01T08:10:00+05:00",
    "end": "2026-10-01T08:32:00+05:00",
    "amount": 2400,
    "payment": "card",
    "commission": 360,
}
STORED_TRIP = TRIP | {
    "start": "2026-10-01T03:10:00Z",
    "end": "2026-10-01T03:32:00Z",
}


def application_with_database(engine: Engine) -> FastAPI:
    application = create_app()

    def session_override() -> Iterator[Session]:
        with Session(engine, expire_on_commit=False) as session:
            yield session

    application.dependency_overrides[get_session] = session_override
    return application


@pytest.fixture
def client(database_engine: Engine) -> Iterator[TestClient]:
    with TestClient(application_with_database(database_engine)) as test_client:
        yield test_client


def assert_single_trip(engine: Engine) -> None:
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(Trip)) == 1


def test_create_commits_trip_and_returns_utc_json(
    client: TestClient, database_engine: Engine
) -> None:
    response = client.post("/api/v1/trips", json=TRIP)

    assert response.status_code == 201
    assert response.headers["content-type"] == "application/json"
    assert response.json() == STORED_TRIP
    assert_single_trip(database_engine)
    day = client.get("/api/v1/days/2026-10-01").json()
    assert day["trips"] == [STORED_TRIP]
    assert day["summary"] == {
        "trip_count": 1,
        "revenue": 2400,
        "commission": 360,
        "net_income": 2040,
        "cash": 0,
        "card": 2400,
    }


@pytest.mark.parametrize(
    "changes",
    [
        {},
        {
            "start": "2026-10-01T03:10:00Z",
            "end": "2026-10-01T04:32:00+01:00",
        },
        {
            "start": "2026-09-30T23:10:00-04:00",
            "end": "2026-10-01T12:32:00+09:00",
        },
    ],
)
def test_repeat_matches_normalized_data_without_changing_day(
    client: TestClient, database_engine: Engine, changes: dict[str, object]
) -> None:
    assert client.post("/api/v1/trips", json=TRIP).status_code == 201
    before = client.get("/api/v1/days/2026-10-01").json()

    response = client.post("/api/v1/trips", json=TRIP | changes)

    assert response.status_code == 200
    assert response.json() == STORED_TRIP
    assert client.get("/api/v1/days/2026-10-01").json() == before
    assert_single_trip(database_engine)


@pytest.mark.parametrize(
    "changes",
    [
        {"start": "2026-10-01T08:11:00+05:00"},
        {"end": "2026-10-01T08:33:00+05:00"},
        {"amount": 2401},
        {"payment": "cash"},
        {"commission": 361},
    ],
)
def test_same_id_changed_data_conflicts_without_changing_day(
    client: TestClient, database_engine: Engine, changes: dict[str, object]
) -> None:
    assert client.post("/api/v1/trips", json=TRIP).status_code == 201
    before = client.get("/api/v1/days/2026-10-01").json()

    response = client.post("/api/v1/trips", json=TRIP | changes)

    assert response.status_code == 409
    assert set(response.json()) == {"detail"}
    assert "t1" in response.json()["detail"]
    assert "Поездка" in response.json()["detail"]
    assert client.get("/api/v1/days/2026-10-01").json() == before
    assert_single_trip(database_engine)
    assert client.post("/api/v1/trips", json=TRIP).status_code == 200


def test_different_ids_with_identical_fields_are_separate_trips(
    client: TestClient, database_engine: Engine
) -> None:
    assert client.post("/api/v1/trips", json=TRIP).status_code == 201
    assert client.post("/api/v1/trips", json=TRIP | {"id": "t2"}).status_code == 201

    day = client.get("/api/v1/days/2026-10-01").json()

    assert {trip["id"] for trip in day["trips"]} == {"t1", "t2"}
    assert day["summary"] == {
        "trip_count": 2,
        "revenue": 4800,
        "commission": 720,
        "net_income": 4080,
        "cash": 0,
        "card": 4800,
    }
    with Session(database_engine) as session:
        assert session.scalar(select(func.count()).select_from(Trip)) == 2


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("id", ""),
        ("id", 1),
        ("id", True),
        ("id", None),
        ("amount", 0),
        ("amount", -1),
        ("amount", 1.5),
        ("amount", 2400.0),
        ("amount", "2400"),
        ("amount", True),
        ("amount", None),
        ("amount", 2**63),
        ("commission", -1),
        ("commission", 1.5),
        ("commission", 360.0),
        ("commission", "360"),
        ("commission", False),
        ("commission", None),
        ("commission", 2**63),
        ("payment", "transfer"),
        ("payment", "CARD"),
        ("payment", None),
        ("start", "2026-10-01T08:10:00"),
        ("end", "2026-10-01T08:32:00"),
        ("start", "2026-02-30T08:10:00+05:00"),
        ("end", "not-a-date"),
        ("start", 1790809800),
        ("end", "1790809800"),
        ("start", None),
        ("end", True),
        ("start", "0001-01-01T00:00:00+05:00"),
        ("end", "9999-12-31T23:59:59-05:00"),
        ("end", "2026-10-01T03:10:00Z"),
        ("end", "2026-10-01T03:09:59Z"),
        ("unexpected", "value"),
    ],
)
def test_invalid_values_return_422_without_changes(
    client: TestClient, database_engine: Engine, field: str, value: object
) -> None:
    assert client.post("/api/v1/trips", json=TRIP).status_code == 201
    before = client.get("/api/v1/days/2026-10-01").json()

    response = client.post("/api/v1/trips", json=TRIP | {"id": "invalid", field: value})

    assert response.status_code == 422
    assert isinstance(response.json()["detail"], list)
    assert client.get("/api/v1/days/2026-10-01").json() == before
    assert_single_trip(database_engine)


@pytest.mark.parametrize("field", tuple(TRIP))
def test_missing_required_fields_return_422(
    client: TestClient, database_engine: Engine, field: str
) -> None:
    payload = TRIP.copy()
    del payload[field]

    response = client.post("/api/v1/trips", json=payload)

    assert response.status_code == 422
    with Session(database_engine) as session:
        assert session.scalar(select(func.count()).select_from(Trip)) == 0


@pytest.mark.parametrize("payload", [None, [], [TRIP], "invalid"])
def test_body_must_be_trip_object(client: TestClient, payload: object) -> None:
    assert client.post("/api/v1/trips", json=payload).status_code == 422


def test_data_and_identity_persist_after_engine_and_application_restart(
    database_engine: Engine,
) -> None:
    with TestClient(application_with_database(database_engine)) as first_client:
        assert first_client.post("/api/v1/trips", json=TRIP).status_code == 201
        before = first_client.get("/api/v1/days/2026-10-01").json()
    database_url = str(database_engine.url)
    database_engine.dispose()
    restarted_engine = create_database_engine(database_url)
    try:
        with TestClient(application_with_database(restarted_engine)) as restarted:
            assert restarted.get("/api/v1/days/2026-10-01").json() == before
            repeat = restarted.post("/api/v1/trips", json=TRIP)
            assert repeat.status_code == 200
            assert repeat.json() == STORED_TRIP
            conflict = restarted.post("/api/v1/trips", json=TRIP | {"amount": 1})
            assert conflict.status_code == 409
            assert restarted.get("/api/v1/days/2026-10-01").json() == before
        assert_single_trip(restarted_engine)
    finally:
        restarted_engine.dispose()


@pytest.mark.parametrize("equivalent", [True, False])
def test_concurrent_http_requests_enforce_database_identity(
    database_engine: Engine, equivalent: bool
) -> None:
    workers = 4
    insert_barrier = Barrier(workers, timeout=10)
    lock = Lock()
    sessions: list[Session] = []
    insert_connections: set[int] = set()

    def synchronize_inserts(
        connection, cursor, statement, parameters, context, executemany
    ) -> None:
        if statement.lstrip().upper().startswith("INSERT INTO TRIPS"):
            with lock:
                insert_connections.add(id(connection))
            insert_barrier.wait()

    def submit(index: int) -> tuple[int, dict[str, object]]:
        application = create_app()

        def session_override() -> Iterator[Session]:
            with Session(database_engine, expire_on_commit=False) as session:
                with lock:
                    sessions.append(session)
                yield session

        application.dependency_overrides[get_session] = session_override
        changes = (
            {
                "start": "2026-10-01T03:10:00Z",
                "end": "2026-10-01T04:32:00+01:00",
            }
            if equivalent and index % 2
            else {}
        )
        if not equivalent:
            changes["amount"] = 2400 + index
        with TestClient(application) as thread_client:
            response = thread_client.post("/api/v1/trips", json=TRIP | changes)
            return response.status_code, response.json()

    event.listen(database_engine, "before_cursor_execute", synchronize_inserts)
    try:
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [executor.submit(submit, index) for index in range(workers)]
            results = [future.result(timeout=20) for future in futures]
    finally:
        event.remove(database_engine, "before_cursor_execute", synchronize_inserts)

    expected_other_status = 200 if equivalent else 409
    assert sorted(status for status, _ in results) == sorted(
        [201] + [expected_other_status] * (workers - 1)
    )
    assert len({id(session) for session in sessions}) == workers
    assert len(insert_connections) == workers
    winner = next(body for status, body in results if status == 201)
    if equivalent:
        assert all(body == STORED_TRIP for _, body in results)
    assert_single_trip(database_engine)
    with TestClient(application_with_database(database_engine)) as reader:
        day = reader.get("/api/v1/days/2026-10-01").json()
        assert day["trips"] == [winner]
        assert day["summary"] == {
            "trip_count": 1,
            "revenue": winner["amount"],
            "commission": 360,
            "net_income": winner["amount"] - 360,
            "cash": 0,
            "card": winner["amount"],
        }


def test_openapi_documents_creation_repeat_conflict_and_validation(
    client: TestClient,
) -> None:
    schema = client.get("/openapi.json").json()
    operation = schema["paths"]["/api/v1/trips"]["post"]
    assert {"200", "201", "409", "422"} <= operation["responses"].keys()
    assert operation["requestBody"]["required"] is True
    for status in ["200", "201", "409", "422"]:
        assert "schema" in operation["responses"][status]["content"]["application/json"]
    request_ref = operation["requestBody"]["content"]["application/json"]["schema"][
        "$ref"
    ]
    request_schema = schema["components"]["schemas"][request_ref.rsplit("/", 1)[1]]
    assert request_schema["additionalProperties"] is False
    assert set(request_schema["required"]) == set(TRIP)
    assert request_schema["properties"]["amount"]["type"] == "integer"
    assert request_schema["properties"]["commission"]["type"] == "integer"
