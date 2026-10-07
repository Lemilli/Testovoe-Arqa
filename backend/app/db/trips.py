from dataclasses import dataclass
from datetime import date

from sqlalchemy import select
from sqlalchemy.dialects.sqlite import insert
from sqlalchemy.orm import Session

from app.db.models import Trip
from app.domain.trips import TripConflictError, TripData, day_bounds_utc


@dataclass(frozen=True)
class SaveTripResult:
    trip: TripData
    created: bool


def save_trip(session: Session, trip: TripData) -> SaveTripResult:
    """Write within the caller's transaction; the primary key decides identity."""
    statement = (
        insert(Trip)
        .values(**trip.model_dump())
        .on_conflict_do_nothing(index_elements=[Trip.id])
        .returning(Trip.id)
    )
    created = session.scalar(statement) is not None
    stored = session.scalar(select(Trip).where(Trip.id == trip.id))
    if stored is None:
        raise RuntimeError("Записанная поездка отсутствует в БД")
    stored_data = TripData.model_validate(stored)
    if stored_data != trip:
        raise TripConflictError(trip.id)
    return SaveTripResult(trip=stored_data, created=created)


def list_trips_for_day(session: Session, day: date) -> tuple[TripData, ...]:
    start, end = day_bounds_utc(day)
    statement = (
        select(Trip)
        .where(Trip.start >= start, Trip.start < end)
        .order_by(Trip.start.desc(), Trip.id.asc())
    )
    return tuple(TripData.model_validate(trip) for trip in session.scalars(statement))
