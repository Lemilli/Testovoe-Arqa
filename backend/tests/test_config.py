from pathlib import Path

import pytest
from pydantic import ValidationError
from sqlalchemy.engine import make_url

from app.core.config import BACKEND_DIRECTORY, Settings, get_settings


def test_default_database_path_is_independent_of_working_directory(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.chdir(tmp_path)

    url = make_url(get_settings().database_url)

    assert url.database == str(BACKEND_DIRECTORY / "driver_diary.db")


def test_database_url_can_be_configured(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    database_url = f"sqlite:///{tmp_path / 'custom.db'}"
    monkeypatch.setenv("DATABASE_URL", database_url)

    assert get_settings().database_url == database_url


@pytest.mark.parametrize("database_url", ["", "not-a-url", "postgresql://localhost/db"])
def test_invalid_database_url_is_rejected(database_url: str) -> None:
    with pytest.raises(ValidationError, match="DATABASE_URL"):
        Settings(database_url=database_url)
