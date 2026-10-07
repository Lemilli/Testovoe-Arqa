"""Import a JSON array of trips after running the database migrations."""

import argparse
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from pydantic import TypeAdapter, ValidationError
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.database import create_database_engine
from app.db.trips import save_trip
from app.domain.trips import TripConflictError, TripData

TRIPS_ADAPTER = TypeAdapter(list[TripData])


@dataclass(frozen=True)
class ImportResult:
    created: int
    repeated: int


def import_trips(session: Session, path: Path) -> ImportResult:
    """Validate the entire file, then import all trips in one transaction."""
    trips = TRIPS_ADAPTER.validate_json(path.read_text(encoding="utf-8"))
    created = 0
    repeated = 0
    with session.begin():
        for trip in trips:
            result = save_trip(session, trip)
            if result.created:
                created += 1
            else:
                repeated += 1
    return ImportResult(created=created, repeated=repeated)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Импорт поездок из UTF-8 JSON в SQLite после миграции Alembic."
    )
    parser.add_argument("path", type=Path, help="Путь к JSON-массиву поездок")
    arguments = parser.parse_args(argv)
    engine = None
    try:
        engine = create_database_engine(get_settings().database_url)
        with Session(engine) as session:
            result = import_trips(session, arguments.path)
    except (OSError, UnicodeError) as error:
        print(f"Не удалось прочитать JSON: {error}", file=sys.stderr)
        return 1
    except ValidationError as error:
        print(f"Некорректный JSON или данные поездок: {error}", file=sys.stderr)
        return 1
    except TripConflictError as error:
        print(
            f"Конфликт ID {error.trip_id!r}: данные поездки отличаются; "
            "импорт отменён.",
            file=sys.stderr,
        )
        return 1
    except OverflowError:
        print(
            "Денежное значение превышает диапазон SQLite INTEGER "
            "(максимум 9223372036854775807 тенге); импорт отменён.",
            file=sys.stderr,
        )
        return 1
    except SQLAlchemyError as error:
        print(
            "Ошибка базы данных. Проверьте DATABASE_URL и выполните "
            f"`uv run --locked alembic upgrade head` перед импортом: {error}",
            file=sys.stderr,
        )
        return 1
    finally:
        if engine is not None:
            engine.dispose()

    print(f"Импорт завершён: создано {result.created}, повторов {result.repeated}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
