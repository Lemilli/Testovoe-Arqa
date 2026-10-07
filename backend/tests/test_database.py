from collections.abc import Iterator
from datetime import UTC, datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import Connection, Engine, inspect, text
from sqlalchemy.exc import IntegrityError, StatementError
from sqlalchemy.orm import Session

from app.core.config import BACKEND_DIRECTORY
from app.db.database import create_database_engine
from app.db.models import Trip


@pytest.fixture
def migrated_engine(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> Iterator[Engine]:
    database_url = f"sqlite:///{tmp_path / 'trips.db'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    command.upgrade(Config(str(BACKEND_DIRECTORY / "alembic.ini")), "head")
    engine = create_database_engine(database_url)
    try:
        yield engine
    finally:
        engine.dispose()


def test_sqlite_session_can_connect_to_file_database(tmp_path: Path) -> None:
    database_path = tmp_path / "connection.db"
    engine = create_database_engine(f"sqlite:///{database_path}")
    try:
        with Session(engine) as session:
            assert session.scalar(text("SELECT 1")) == 1
        assert database_path.is_file()
    finally:
        engine.dispose()


def test_alembic_upgrade_matches_metadata_and_can_downgrade(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    database_url = f"sqlite:///{tmp_path / 'migrations.db'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    config = Config(str(BACKEND_DIRECTORY / "alembic.ini"))

    command.upgrade(config, "head")
    command.check(config)

    engine = create_database_engine(database_url)
    try:
        inspector = inspect(engine)
        assert inspector.get_table_names() == ["alembic_version", "trips"]
        assert inspector.get_pk_constraint("trips")["constrained_columns"] == ["id"]
        assert {column["name"] for column in inspector.get_columns("trips")} == {
            "id",
            "start",
            "end",
            "amount",
            "payment",
            "commission",
        }
        assert all(not column["nullable"] for column in inspector.get_columns("trips"))
        assert inspector.get_indexes("trips") == [
            {
                "name": "ix_trips_start",
                "column_names": ["start"],
                "unique": 0,
                "dialect_options": {},
            }
        ]
        with engine.connect() as connection:
            assert connection.scalar(
                text("SELECT version_num FROM alembic_version")
            ) == ("0001_create_trips")

        command.downgrade(config, "base")
        assert inspect(engine).get_table_names() == ["alembic_version"]
        command.upgrade(config, "head")
        command.check(config)
    finally:
        engine.dispose()


def test_trip_timestamps_are_normalized_to_utc_and_survive_reconnection(
    migrated_engine: Engine,
) -> None:
    local_start = datetime(2026, 10, 1, 8, 10, tzinfo=timezone(timedelta(hours=5)))
    local_end = local_start + timedelta(minutes=22)
    with Session(migrated_engine) as session:
        session.add(
            Trip(
                id="t1",
                start=local_start,
                end=local_end,
                amount=2400,
                payment="card",
                commission=360,
            )
        )
        session.commit()

    with migrated_engine.connect() as connection:
        stored = connection.execute(text('SELECT start, "end" FROM trips')).one()
        assert stored == ("2026-10-01 03:10:00.000000", "2026-10-01 03:32:00.000000")

    reopened_engine = create_database_engine(str(migrated_engine.url))
    try:
        with Session(reopened_engine) as session:
            trip = session.get(Trip, "t1")
            assert trip is not None
            assert trip.start == datetime(2026, 10, 1, 3, 10, tzinfo=UTC)
            assert trip.end == datetime(2026, 10, 1, 3, 32, tzinfo=UTC)
            assert trip.start.tzinfo is UTC
            assert trip.end.tzinfo is UTC
            assert trip.amount == 2400
            assert trip.commission == 360
    finally:
        reopened_engine.dispose()


@pytest.mark.parametrize("timestamp_field", ["start", "end"])
def test_trip_rejects_naive_timestamps(
    migrated_engine: Engine, timestamp_field: str
) -> None:
    values = {
        "id": "t1",
        "start": datetime(2026, 10, 1, 3, 10, tzinfo=UTC),
        "end": datetime(2026, 10, 1, 3, 32, tzinfo=UTC),
        "amount": 2400,
        "payment": "card",
        "commission": 360,
    }
    values[timestamp_field] = datetime(2026, 10, 1, 3, 20)
    with Session(migrated_engine) as session:
        session.add(Trip(**values))
        with pytest.raises(StatementError, match="must include a timezone offset"):
            session.commit()


def insert_trip(connection: Connection, **overrides: object) -> None:
    """Use raw SQL so constraints are exercised without model validation."""
    values = {
        "id": "t1",
        "start": "2026-10-01 03:10:00.000000",
        "end": "2026-10-01 03:32:00.000000",
        "amount": 2400,
        "payment": "card",
        "commission": 360,
    }
    values.update(overrides)
    connection.execute(
        text(
            'INSERT INTO trips (id, start, "end", amount, payment, commission) '
            "VALUES (:id, :start, :end, :amount, :payment, :commission)"
        ),
        values,
    )


@pytest.mark.parametrize(
    "overrides",
    [
        {"amount": 0},
        {"amount": -1},
        {"amount": 2400.5},
        {"amount": "invalid"},
        {"commission": -1},
        {"commission": 360.5},
        {"commission": "invalid"},
        {"payment": "other"},
        {"end": "2026-10-01 03:10:00.000000"},
        {"end": "2026-10-01 03:09:59.000000"},
        {"id": None},
        {"start": None},
        {"end": None},
        {"amount": None},
        {"payment": None},
        {"commission": None},
    ],
)
def test_database_constraints_reject_invalid_data(
    migrated_engine: Engine, overrides: dict[str, object]
) -> None:
    with migrated_engine.begin() as connection:
        with pytest.raises(IntegrityError):
            insert_trip(connection, **overrides)
        assert connection.scalar(text("SELECT COUNT(*) FROM trips")) == 0


def test_database_primary_key_prevents_duplicate_trip_ids(
    migrated_engine: Engine,
) -> None:
    with migrated_engine.begin() as connection:
        insert_trip(connection)
        with pytest.raises(IntegrityError):
            insert_trip(connection, amount=1500)
        assert connection.scalar(text("SELECT COUNT(*) FROM trips")) == 1


def test_database_allows_zero_commission_and_commission_above_amount(
    migrated_engine: Engine,
) -> None:
    with migrated_engine.begin() as connection:
        insert_trip(connection, id="zero", commission=0)
        insert_trip(connection, id="greater", commission=3000)
        assert connection.scalar(text("SELECT COUNT(*) FROM trips")) == 2
