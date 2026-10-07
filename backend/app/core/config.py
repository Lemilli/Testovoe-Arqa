import os
from pathlib import Path

from pydantic import BaseModel, ConfigDict, field_validator
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

BACKEND_DIRECTORY = Path(__file__).resolve().parents[2]
DEFAULT_DATABASE_URL = f"sqlite:///{BACKEND_DIRECTORY / 'driver_diary.db'}"


class Settings(BaseModel):
    model_config = ConfigDict(frozen=True)

    database_url: str = DEFAULT_DATABASE_URL

    @field_validator("database_url")
    @classmethod
    def validate_database_url(cls, value: str) -> str:
        try:
            url = make_url(value)
        except ArgumentError as error:
            raise ValueError(
                "DATABASE_URL должен быть корректным SQLite URL"
            ) from error
        if url.drivername not in {"sqlite", "sqlite+pysqlite"}:
            raise ValueError("DATABASE_URL должен использовать SQLite")
        return value


def get_settings() -> Settings:
    return Settings(database_url=os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL))
