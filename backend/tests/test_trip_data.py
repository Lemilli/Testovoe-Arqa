from datetime import UTC, date, datetime

import pytest
from pydantic import ValidationError

from app.domain.trips import TripData, day_bounds_utc


def trip_fields() -> dict[str, object]:
    return {
        "id": "t1",
        "start": "2026-10-01T08:10:00+05:00",
        "end": "2026-10-01T08:32:00+05:00",
        "amount": 2400,
        "payment": "card",
        "commission": 360,
    }


def test_trip_normalizes_offsets_to_utc() -> None:
    trip = TripData.model_validate(trip_fields())
    equivalent = TripData.model_validate(
        trip_fields()
        | {"start": "2026-10-01T03:10:00Z", "end": "2026-09-30T23:32:00-04:00"}
    )

    assert trip == equivalent
    assert trip.start == datetime(2026, 10, 1, 3, 10, tzinfo=UTC)
    assert trip.start.tzinfo is UTC
    assert trip.end.tzinfo is UTC


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("amount", 0),
        ("amount", -1),
        ("amount", 1.5),
        ("amount", 2400.0),
        ("amount", "2400"),
        ("amount", True),
        ("commission", -1),
        ("commission", 1.5),
        ("commission", 360.0),
        ("commission", "360"),
        ("commission", False),
        ("payment", "transfer"),
        ("payment", "CARD"),
        ("id", ""),
        ("id", 1),
        ("start", "2026-10-01T08:10:00"),
        ("end", datetime(2026, 10, 1, 8, 32)),
        ("start", "2026-02-30T08:10:00+05:00"),
        ("start", "not-a-date"),
        ("start", 1790809800),
        ("start", "1790809800"),
        ("start", "0001-01-01T00:00:00+05:00"),
        ("end", "9999-12-31T23:59:59-05:00"),
        ("end", "2026-10-01T03:10:00Z"),
        ("end", "2026-10-01T03:09:59Z"),
    ],
)
def test_invalid_trip_is_rejected(field: str, value: object) -> None:
    with pytest.raises(ValidationError):
        TripData.model_validate(trip_fields() | {field: value})


def test_commission_can_be_zero_or_exceed_revenue() -> None:
    assert TripData.model_validate(trip_fields() | {"commission": 0}).commission == 0
    assert (
        TripData.model_validate(trip_fields() | {"commission": 3000}).commission == 3000
    )


def test_almaty_day_bounds_are_half_open_utc_interval() -> None:
    assert day_bounds_utc(date(2026, 10, 1)) == (
        datetime(2026, 9, 30, 19, tzinfo=UTC),
        datetime(2026, 10, 1, 19, tzinfo=UTC),
    )


def test_day_bounds_use_timezone_rules_instead_of_fixed_offset() -> None:
    assert day_bounds_utc(date(2024, 2, 29)) == (
        datetime(2024, 2, 28, 18, tzinfo=UTC),
        datetime(2024, 2, 29, 19, tzinfo=UTC),
    )
