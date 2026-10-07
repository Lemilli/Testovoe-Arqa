from datetime import UTC, datetime

from sqlalchemy import CheckConstraint, DateTime, Integer, String
from sqlalchemy.engine import Dialect
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import TypeDecorator

from app.db.database import Base


class UTCDateTime(TypeDecorator[datetime]):
    """Store UTC instants and restore the timezone lost by SQLite DATETIME."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(
        self, value: datetime | None, dialect: Dialect
    ) -> datetime | None:
        if value is None:
            return None
        if value.utcoffset() is None:
            raise ValueError("Trip timestamps must include a timezone offset")
        normalized = value.astimezone(UTC)
        if dialect.name == "sqlite":
            return normalized.replace(tzinfo=None)
        return normalized

    def process_result_value(
        self, value: datetime | None, dialect: Dialect
    ) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)


class Trip(Base):
    __tablename__ = "trips"
    __table_args__ = (
        CheckConstraint("amount > 0", name="ck_trips_amount_positive"),
        CheckConstraint("commission >= 0", name="ck_trips_commission_nonnegative"),
        CheckConstraint("payment IN ('cash', 'card')", name="ck_trips_payment"),
        CheckConstraint('"end" > start', name="ck_trips_end_after_start"),
        CheckConstraint("typeof(amount) = 'integer'", name="ck_trips_amount_integer"),
        CheckConstraint(
            "typeof(commission) = 'integer'", name="ck_trips_commission_integer"
        ),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True)
    start: Mapped[datetime] = mapped_column(UTCDateTime, index=True)
    end: Mapped[datetime] = mapped_column(UTCDateTime)
    amount: Mapped[int] = mapped_column(Integer)
    payment: Mapped[str] = mapped_column(String)
    commission: Mapped[int] = mapped_column(Integer)
