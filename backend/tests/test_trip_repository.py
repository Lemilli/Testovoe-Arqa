from datetime import date

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import Trip
from app.db.trips import save_trip
from app.domain.trips import TripConflictError, TripData
from app.services.days import get_day


def trip_data(**changes: object) -> TripData:
    return TripData.model_validate(
        {
            "id": "same",
            "start": "2026-10-01T08:10:00+05:00",
            "end": "2026-10-01T08:32:00+05:00",
            "amount": 2400,
            "payment": "card",
            "commission": 360,
        }
        | changes
    )


def test_repeat_uses_normalized_time_and_keeps_one_row(db_session: Session) -> None:
    with db_session.begin():
        first = save_trip(db_session, trip_data())
    with db_session.begin():
        repeated = save_trip(
            db_session,
            trip_data(start="2026-10-01T03:10:00Z", end="2026-10-01T04:32:00+01:00"),
        )

    assert first.created is True
    assert repeated.created is False
    assert first.trip == repeated.trip
    assert db_session.scalar(select(func.count()).select_from(Trip)) == 1


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
def test_same_id_with_changed_data_is_conflict(
    db_session: Session, changes: dict[str, object]
) -> None:
    with db_session.begin():
        save_trip(db_session, trip_data())
    with pytest.raises(TripConflictError) as error, db_session.begin():
        save_trip(db_session, trip_data(**changes))

    assert error.value.trip_id == "same"
    assert get_day(db_session, date(2026, 10, 1)).trips == (trip_data(),)


def test_different_ids_are_different_trips(db_session: Session) -> None:
    with db_session.begin():
        assert save_trip(db_session, trip_data(id="b")).created
        assert save_trip(db_session, trip_data(id="a")).created

    day = get_day(db_session, date(2026, 10, 1))
    assert [trip.id for trip in day.trips] == ["a", "b"]
    assert day.summary.trip_count == 2
    assert day.summary.revenue == 4800
