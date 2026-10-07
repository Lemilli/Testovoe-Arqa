from sqlalchemy.orm import Session

from app.db.trips import SaveTripResult, save_trip
from app.domain.trips import TripData


def add_trip(session: Session, trip: TripData) -> SaveTripResult:
    """Commit creation/repeat before HTTP success; a conflict rolls back."""
    with session.begin():
        result = save_trip(session, trip)
    return result
