from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from typing import Literal, Self
from zoneinfo import ZoneInfo

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    StrictStr,
    field_validator,
    model_validator,
)

ALMATY_TIMEZONE = ZoneInfo("Asia/Almaty")


class TripData(BaseModel):
    """Validated trip data shared by import and persistence, independent of HTTP."""

    model_config = ConfigDict(frozen=True, extra="forbid", from_attributes=True)

    id: StrictStr = Field(min_length=1)
    start: AwareDatetime
    end: AwareDatetime
    amount: StrictInt = Field(gt=0)
    payment: Literal["cash", "card"]
    commission: StrictInt = Field(ge=0)

    @field_validator("start", "end", mode="before")
    @classmethod
    def parse_iso_datetime(cls, value: object) -> datetime:
        if isinstance(value, datetime):
            return value
        if isinstance(value, str):
            try:
                return datetime.fromisoformat(value)
            except ValueError as error:
                raise ValueError("Время должно быть в формате ISO 8601") from error
        raise ValueError("Время должно содержать дату и часовое смещение")

    @field_validator("start", "end")
    @classmethod
    def normalize_datetime(cls, value: datetime) -> datetime:
        try:
            return value.astimezone(UTC)
        except OverflowError as error:
            raise ValueError("Время в UTC выходит за допустимый диапазон") from error

    @model_validator(mode="after")
    def validate_interval(self) -> Self:
        if self.end <= self.start:
            raise ValueError("Окончание поездки должно быть строго позже начала")
        return self


class TripConflictError(ValueError):
    def __init__(self, trip_id: str) -> None:
        self.trip_id = trip_id
        super().__init__(f"Поездка с ID {trip_id!r} уже существует с другими данными")


@dataclass(frozen=True)
class DaySummary:
    trip_count: int = 0
    revenue: int = 0
    commission: int = 0
    net_income: int = 0
    cash: int = 0
    card: int = 0


@dataclass(frozen=True)
class DayData:
    date: date
    trips: tuple[TripData, ...]
    summary: DaySummary


def day_bounds_utc(day: date) -> tuple[datetime, datetime]:
    """Half-open Almaty calendar day, converted using the IANA timezone rules."""
    start = datetime.combine(day, time.min, ALMATY_TIMEZONE)
    end = datetime.combine(day + timedelta(days=1), time.min, ALMATY_TIMEZONE)
    return start.astimezone(UTC), end.astimezone(UTC)
