from collections.abc import Iterable
from datetime import date

from sqlalchemy.orm import Session

from app.db.trips import list_trips_for_day
from app.domain.trips import DayData, DaySummary, TripData


def summarize_trips(trips: Iterable[TripData]) -> DaySummary:
    trip_count = revenue = commission = cash = card = 0
    for trip in trips:
        trip_count += 1
        revenue += trip.amount
        commission += trip.commission
        if trip.payment == "cash":
            cash += trip.amount
        else:
            card += trip.amount
    return DaySummary(
        trip_count=trip_count,
        revenue=revenue,
        commission=commission,
        net_income=revenue - commission,
        cash=cash,
        card=card,
    )


def get_day(session: Session, day: date) -> DayData:
    trips = list_trips_for_day(session, day)
    return DayData(date=day, trips=trips, summary=summarize_trips(trips))
