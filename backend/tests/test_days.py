import os
import time
from datetime import date

import pytest
from sqlalchemy.orm import Session

from app.db.trips import save_trip
from app.domain.trips import DaySummary, TripData
from app.services.days import get_day, summarize_trips


def make_trip(
    trip_id: str,
    start: str = "2026-10-01T08:10:00+05:00",
    end: str = "2026-10-01T08:32:00+05:00",
    amount: int = 2400,
    commission: int = 360,
    payment: str = "card",
) -> TripData:
    return TripData.model_validate(
        {
            "id": trip_id,
            "start": start,
            "end": end,
            "amount": amount,
            "commission": commission,
            "payment": payment,
        }
    )


def test_control_summary_and_newest_first(db_session: Session) -> None:
    first = make_trip("t1")
    second = make_trip(
        "t2",
        start="2026-10-01T09:05:00+05:00",
        end="2026-10-01T09:20:00+05:00",
        amount=1500,
        commission=225,
        payment="cash",
    )
    with db_session.begin():
        save_trip(db_session, first)
        save_trip(db_session, second)

    day = get_day(db_session, date(2026, 10, 1))

    assert day.date == date(2026, 10, 1)
    assert day.trips == (second, first)
    assert day.summary == DaySummary(2, 3900, 585, 3315, 1500, 2400)


def test_empty_day_has_empty_list_and_zero_summary(db_session: Session) -> None:
    with db_session.begin():
        save_trip(db_session, make_trip("another-day"))

    day = get_day(db_session, date(2026, 10, 2))

    assert day.trips == ()
    assert day.summary == DaySummary()


@pytest.mark.parametrize("payment", ["cash", "card"])
def test_integer_precision_and_payment_revenue(payment: str) -> None:
    amount = 2**53 + 1
    trips = [
        make_trip("large", amount=amount, commission=0, payment=payment),
        make_trip("small", amount=7, commission=2, payment=payment),
    ]

    summary = summarize_trips(iter(trips))

    assert summary.revenue == amount + 7
    assert summary.commission == 2
    assert summary.net_income == amount + 5
    assert summary.cash + summary.card == summary.revenue
    assert (summary.cash if payment == "cash" else summary.card) == amount + 7
    assert (summary.card if payment == "cash" else summary.cash) == 0
    assert all(type(value) is int for value in vars(summary).values())


def test_summary_can_exceed_sqlite_integer_range(db_session: Session) -> None:
    with db_session.begin():
        save_trip(db_session, make_trip("a", amount=2**63 - 1))
        save_trip(db_session, make_trip("b", amount=2**63 - 1))

    summary = get_day(db_session, date(2026, 10, 1)).summary

    assert summary.revenue == 2 * (2**63 - 1)
    assert summary.net_income == 2 * (2**63 - 1) - 720


def test_commission_is_money_and_net_income_can_be_negative() -> None:
    summary = summarize_trips([make_trip("loss", amount=100, commission=150)])

    assert summary == DaySummary(1, 100, 150, -50, 0, 100)


def test_midnight_boundaries_offsets_and_cross_midnight(db_session: Session) -> None:
    trips = [
        make_trip(
            "before",
            "2026-09-30T23:59:59.999999+05:00",
            "2026-10-01T00:10:00+05:00",
        ),
        make_trip("midnight", "2026-09-30T19:00:00Z", "2026-09-30T19:10:00Z"),
        make_trip(
            "cross-midnight", "2026-10-01T23:50:00+05:00", "2026-10-02T00:20:00+05:00"
        ),
        make_trip(
            "last-microsecond",
            "2026-10-01T23:59:59.999999+05:00",
            "2026-10-02T00:10:00+05:00",
        ),
        make_trip("next-midnight", "2026-10-02T03:00:00+08:00", "2026-10-01T19:10:00Z"),
    ]
    with db_session.begin():
        for trip in trips:
            save_trip(db_session, trip)

    selected = get_day(db_session, date(2026, 10, 1))

    assert [trip.id for trip in selected.trips] == [
        "last-microsecond",
        "cross-midnight",
        "midnight",
    ]
    assert selected.summary.trip_count == 3
    assert [trip.id for trip in get_day(db_session, date(2026, 9, 30)).trips] == [
        "before"
    ]
    assert [trip.id for trip in get_day(db_session, date(2026, 10, 2)).trips] == [
        "next-midnight"
    ]


@pytest.mark.parametrize("timezone", ["UTC", "America/New_York", "Asia/Tokyo"])
def test_day_is_independent_of_process_timezone(
    db_session: Session, timezone: str
) -> None:
    with db_session.begin():
        save_trip(db_session, make_trip("midnight", "2026-09-30T19:00:00Z"))
    previous = os.environ.get("TZ")
    try:
        os.environ["TZ"] = timezone
        time.tzset()
        day = get_day(db_session, date(2026, 10, 1))
        assert [trip.id for trip in day.trips] == ["midnight"]
        assert day.summary == DaySummary(1, 2400, 360, 2040, 0, 2400)
    finally:
        if previous is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = previous
        time.tzset()
