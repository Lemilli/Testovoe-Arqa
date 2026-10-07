from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import Engine
from sqlalchemy.orm import Session

from app.core.config import BACKEND_DIRECTORY
from app.db.database import create_database_engine


@pytest.fixture
def database_engine(
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


@pytest.fixture
def db_session(database_engine: Engine) -> Iterator[Session]:
    with Session(database_engine, expire_on_commit=False) as session:
        yield session
