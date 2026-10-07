from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from app.core.config import BACKEND_DIRECTORY
from app.db.database import create_database_engine


def test_sqlite_session_can_connect_to_file_database(tmp_path: Path) -> None:
    database_path = tmp_path / "connection.db"
    engine = create_database_engine(f"sqlite:///{database_path}")
    try:
        with Session(engine) as session:
            assert session.scalar(text("SELECT 1")) == 1
        assert database_path.is_file()
    finally:
        engine.dispose()


def test_alembic_environment_runs_on_empty_database(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    database_url = f"sqlite:///{tmp_path / 'migrations.db'}"
    monkeypatch.setenv("DATABASE_URL", database_url)
    config = Config(str(BACKEND_DIRECTORY / "alembic.ini"))

    command.upgrade(config, "head")
    command.check(config)

    engine = create_database_engine(database_url)
    try:
        assert inspect(engine).get_table_names() == ["alembic_version"]
        with engine.connect() as connection:
            assert connection.scalar(text("SELECT COUNT(*) FROM alembic_version")) == 0
    finally:
        engine.dispose()
