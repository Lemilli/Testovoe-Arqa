import json
from pathlib import Path

from fastapi.testclient import TestClient
from sqlalchemy import Engine, event, func, select
from sqlalchemy.orm import Session

from app.core.config import BACKEND_DIRECTORY
from app.db.models import Trip
from app.import_trips import ImportResult, import_trips
from app.main import create_app

DEMO_PATH = BACKEND_DIRECTORY / "data" / "trips.json"


def test_default_sessions_use_configured_database_and_survive_app_restart(
    database_engine: Engine,
) -> None:
    trip = json.loads(DEMO_PATH.read_text(encoding="utf-8"))[0]
    application = create_app()
    with TestClient(application) as client:
        # No dependency override: startup reads DATABASE_URL and creates its engine.
        assert application.state.session_factory.kw["bind"].url == database_engine.url
        created = client.post("/api/v1/trips", json=trip)
        assert created.status_code == 201
        day = client.get("/api/v1/days/2026-10-01")
        assert day.status_code == 200
        assert day.json()["trips"] == [created.json()]

    with Session(database_engine) as session:
        assert session.scalar(select(func.count()).select_from(Trip)) == 1

    with TestClient(create_app()) as client:
        repeated = client.post("/api/v1/trips", json=trip)
        assert repeated.status_code == 200
        assert repeated.json() == created.json()
        assert client.get("/api/v1/days/2026-10-01").json()["summary"] == {
            "trip_count": 1,
            "revenue": 2400,
            "commission": 360,
            "net_income": 2040,
            "cash": 0,
            "card": 2400,
        }


def test_import_and_api_share_normalized_identity(
    database_engine: Engine, tmp_path: Path
) -> None:
    with Session(database_engine) as session:
        assert import_trips(session, DEMO_PATH) == ImportResult(2, 0)
    trip = json.loads(DEMO_PATH.read_text(encoding="utf-8"))[0]
    equivalent = {
        **trip,
        "start": "2026-10-01T03:10:00Z",
        "end": "2026-09-30T23:32:00-04:00",
    }
    with TestClient(create_app()) as client:
        assert client.post("/api/v1/trips", json=equivalent).status_code == 200
        assert (
            client.post(
                "/api/v1/trips", json={**equivalent, "commission": 361}
            ).status_code
            == 409
        )
        assert (
            client.post("/api/v1/trips", json={**trip, "id": "from-api"}).status_code
            == 201
        )

    from_api = tmp_path / "from-api.json"
    from_api.write_text(
        json.dumps([{**equivalent, "id": "from-api"}]), encoding="utf-8"
    )
    with Session(database_engine) as session:
        assert import_trips(session, from_api) == ImportResult(0, 1)
        assert session.scalar(select(func.count()).select_from(Trip)) == 3


def test_commit_failure_rolls_back_before_any_success_response(
    database_engine: Engine,
) -> None:
    trip = json.loads(DEMO_PATH.read_text(encoding="utf-8"))[0]

    def fail_commit(session: Session) -> None:
        raise RuntimeError("Simulated commit failure")

    application = create_app()
    with TestClient(application, raise_server_exceptions=False) as client:
        factory = application.state.session_factory
        event.listen(factory, "before_commit", fail_commit)
        try:
            failed = client.post("/api/v1/trips", json=trip)
        finally:
            event.remove(factory, "before_commit", fail_commit)

        assert failed.status_code == 500
        with Session(database_engine) as session:
            assert session.scalar(select(func.count()).select_from(Trip)) == 0
        day = client.get("/api/v1/days/2026-10-01").json()
        assert day["summary"]["trip_count"] == 0
        assert client.post("/api/v1/trips", json=trip).status_code == 201
