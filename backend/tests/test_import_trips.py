import json
import os
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from pydantic import ValidationError
from sqlalchemy import Engine, text
from sqlalchemy.orm import Session

from app.core.config import BACKEND_DIRECTORY
from app.db.database import create_database_engine
from app.domain.trips import TripConflictError
from app.import_trips import ImportResult, import_trips

DEMO_PATH = BACKEND_DIRECTORY / "data" / "trips.json"


@pytest.fixture
def import_database(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> Iterator[tuple[Engine, str]]:
    database_url = f"sqlite:///{tmp_path / 'import.db'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    command.upgrade(Config(str(BACKEND_DIRECTORY / "alembic.ini")), "head")
    engine = create_database_engine(database_url)
    try:
        yield engine, database_url
    finally:
        engine.dispose()


def write_trips(tmp_path: Path, trips: object) -> Path:
    path = tmp_path / "input.json"
    path.write_text(json.dumps(trips), encoding="utf-8")
    return path


def demo_trips() -> list[dict[str, object]]:
    return json.loads(DEMO_PATH.read_text(encoding="utf-8"))


def import_file(engine: Engine, path: Path) -> ImportResult:
    with Session(engine) as session:
        return import_trips(session, path)


def trip_count(engine: Engine) -> int:
    with engine.connect() as connection:
        return connection.scalar(text("SELECT COUNT(*) FROM trips"))


def run_import_cli(database_url: str, path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "app.import_trips", str(path)],
        cwd=BACKEND_DIRECTORY,
        env={**os.environ, "DATABASE_URL": database_url},
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_demo_import_and_repeat(import_database: tuple[Engine, str]) -> None:
    engine, _ = import_database
    assert import_file(engine, DEMO_PATH) == ImportResult(created=2, repeated=0)
    assert import_file(engine, DEMO_PATH) == ImportResult(created=0, repeated=2)
    assert trip_count(engine) == 2


def test_repeated_instants_with_different_offsets(
    import_database: tuple[Engine, str], tmp_path: Path
) -> None:
    engine, _ = import_database
    import_file(engine, DEMO_PATH)
    trips = demo_trips()
    trips[0]["start"] = "2026-10-01T03:10:00Z"
    trips[0]["end"] = "2026-10-01T05:32:00+02:00"
    assert import_file(engine, write_trips(tmp_path, trips)) == ImportResult(
        created=0, repeated=2
    )
    assert trip_count(engine) == 2


def test_different_ids_with_identical_fields_are_separate_trips(
    import_database: tuple[Engine, str], tmp_path: Path
) -> None:
    engine, _ = import_database
    trip = demo_trips()[0]
    path = write_trips(tmp_path, [trip, {**trip, "id": "another-trip"}])
    assert import_file(engine, path) == ImportResult(created=2, repeated=0)
    assert trip_count(engine) == 2


def test_identical_ids_with_identical_fields_in_one_file_are_repeats(
    import_database: tuple[Engine, str], tmp_path: Path
) -> None:
    engine, _ = import_database
    trip = demo_trips()[0]
    assert import_file(engine, write_trips(tmp_path, [trip, trip])) == ImportResult(
        created=1, repeated=1
    )
    assert trip_count(engine) == 1


@pytest.mark.parametrize("existing", [False, True])
def test_conflict_rolls_back_entire_file(
    import_database: tuple[Engine, str], tmp_path: Path, existing: bool
) -> None:
    engine, _ = import_database
    trip = demo_trips()[0]
    if existing:
        import_file(engine, write_trips(tmp_path, [trip]))
    conflict = {**trip, "amount": 2500}
    new_trip = {**trip, "id": "new-trip"}
    contents = [new_trip, conflict] if existing else [new_trip, trip, conflict]
    with pytest.raises(TripConflictError) as error:
        import_file(engine, write_trips(tmp_path, contents))
    assert error.value.trip_id == "t1"
    assert trip_count(engine) == int(existing)
    # The rolled-back session does not poison future imports.
    assert import_file(engine, DEMO_PATH) == ImportResult(
        created=1 if existing else 2, repeated=1 if existing else 0
    )


@pytest.mark.parametrize(
    "invalid_fields",
    [
        {"amount": 0},
        {"amount": 1.5},
        {"amount": True},
        {"commission": -1},
        {"commission": 1.5},
        {"payment": "crypto"},
        {"start": "2026-10-01T08:10:00"},
        {"end": "2026-10-01T08:10:00+05:00"},
    ],
)
def test_whole_file_is_validated_before_writing(
    import_database: tuple[Engine, str], tmp_path: Path, invalid_fields: dict
) -> None:
    engine, _ = import_database
    trip = demo_trips()[0]
    invalid = {**demo_trips()[1], **invalid_fields}
    # For the second trip, the invalid end must be before its own start.
    path = write_trips(tmp_path, [trip, invalid])
    with pytest.raises(ValidationError):
        import_file(engine, path)
    assert trip_count(engine) == 0


def test_empty_array_is_a_successful_empty_import(
    import_database: tuple[Engine, str], tmp_path: Path
) -> None:
    engine, _ = import_database
    assert import_file(engine, write_trips(tmp_path, [])) == ImportResult(
        created=0, repeated=0
    )
    assert trip_count(engine) == 0


@pytest.mark.parametrize("contents", ["[", "{}", "null", '{"trips": []}'])
def test_malformed_or_non_array_json_is_rejected(
    import_database: tuple[Engine, str], tmp_path: Path, contents: str
) -> None:
    engine, _ = import_database
    path = tmp_path / "invalid.json"
    path.write_text(contents, encoding="utf-8")
    with pytest.raises(ValidationError):
        import_file(engine, path)
    assert trip_count(engine) == 0


def test_cli_restarts_reuse_database_and_preserve_data(
    import_database: tuple[Engine, str], tmp_path: Path
) -> None:
    engine, database_url = import_database
    first = run_import_cli(database_url, DEMO_PATH)
    assert first.returncode == 0, first.stderr
    assert "создано 2, повторов 0" in first.stdout
    engine.dispose()

    second = run_import_cli(database_url, DEMO_PATH)
    assert second.returncode == 0, second.stderr
    assert "создано 0, повторов 2" in second.stdout
    # An independent process opens SQLite again and checks persisted IDs and money.
    read = subprocess.run(
        [
            sys.executable,
            "-c",
            "import json; "
            "from app.core.config import get_settings; "
            "from app.db.database import create_database_engine; "
            "from sqlalchemy import text; "
            "engine = create_database_engine(get_settings().database_url); "
            "connection = engine.connect(); "
            "rows = connection.execute(text('SELECT id, amount, payment, commission "
            "FROM trips ORDER BY id')).all(); "
            "print(json.dumps([list(row) for row in rows])); "
            "connection.close(); engine.dispose()",
        ],
        cwd=BACKEND_DIRECTORY,
        env={**os.environ, "DATABASE_URL": database_url},
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert json.loads(read.stdout) == [
        ["t1", 2400, "card", 360],
        ["t2", 1500, "cash", 225],
    ]

    conflicting = demo_trips()
    conflicting[0]["commission"] = 500
    third = run_import_cli(database_url, write_trips(tmp_path, conflicting))
    assert third.returncode == 1
    assert "Конфликт ID 't1'" in third.stderr
    assert "импорт отменён" in third.stderr
    assert trip_count(engine) == 2


@pytest.mark.parametrize("failure", ["missing", "malformed", "non-array", "invalid"])
def test_cli_reports_input_errors(
    import_database: tuple[Engine, str], tmp_path: Path, failure: str
) -> None:
    engine, database_url = import_database
    path = tmp_path / "input.json"
    if failure == "malformed":
        path.write_text("[", encoding="utf-8")
    elif failure == "non-array":
        path.write_text("{}", encoding="utf-8")
    elif failure == "invalid":
        path = write_trips(tmp_path, [{**demo_trips()[0], "amount": 0}])
    result = run_import_cli(database_url, path)
    assert result.returncode == 1
    assert result.stderr
    assert "Traceback" not in result.stderr
    assert trip_count(engine) == 0


def test_cli_requires_explicit_migrations(tmp_path: Path) -> None:
    database_url = f"sqlite:///{tmp_path / 'unmigrated.db'}"
    result = run_import_cli(database_url, DEMO_PATH)
    assert result.returncode == 1
    assert "alembic upgrade head" in result.stderr
    assert "Traceback" not in result.stderr
    engine = create_database_engine(database_url)
    try:
        with engine.connect() as connection:
            assert (
                connection.scalar(
                    text("SELECT COUNT(*) FROM sqlite_master WHERE type='table'")
                )
                == 0
            )
    finally:
        engine.dispose()


@pytest.mark.parametrize("field", ["amount", "commission"])
def test_cli_reports_sqlite_integer_overflow_and_rolls_back(
    import_database: tuple[Engine, str], tmp_path: Path, field: str
) -> None:
    engine, database_url = import_database
    trips = demo_trips()
    trips[1][field] = 2**63

    result = run_import_cli(database_url, write_trips(tmp_path, trips))

    assert result.returncode == 1
    assert "диапазон SQLite INTEGER" in result.stderr
    assert "импорт отменён" in result.stderr
    assert "Traceback" not in result.stderr
    assert trip_count(engine) == 0
