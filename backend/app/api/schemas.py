import re
from datetime import date
from typing import Annotated

from pydantic import (
    AfterValidator,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    StrictInt,
)

from app.domain.trips import TripData, day_bounds_utc

SQLITE_INTEGER_MAX = 2**63 - 1


class TripCreate(TripData):
    """A trip in KZT; timestamps require an explicit ISO 8601 UTC offset."""

    amount: StrictInt = Field(
        gt=0,
        le=SQLITE_INTEGER_MAX,
        description="Выручка в целых тенге (KZT), максимум 9223372036854775807",
    )
    commission: StrictInt = Field(
        ge=0,
        le=SQLITE_INTEGER_MAX,
        description="Комиссия в целых тенге (KZT), максимум 9223372036854775807",
    )


class SummaryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    trip_count: StrictInt = Field(ge=0)
    revenue: StrictInt = Field(ge=0, description="Выручка в тенге")
    commission: StrictInt = Field(ge=0, description="Комиссия в тенге")
    net_income: StrictInt = Field(description="Выручка минус комиссия, в тенге")
    cash: StrictInt = Field(ge=0, description="Выручка наличными, в тенге")
    card: StrictInt = Field(ge=0, description="Выручка картой, в тенге")


class DayResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    date: date
    trips: tuple[TripData, ...]
    summary: SummaryResponse


class ConflictResponse(BaseModel):
    detail: str


def parse_day(value: object) -> date:
    if not isinstance(value, str) or not re.fullmatch(
        r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value
    ):
        raise ValueError("Дата должна быть в формате YYYY-MM-DD")
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise ValueError("Указана неверная календарная дата") from error


def validate_day_range(day: date) -> date:
    try:
        day_bounds_utc(day)
    except (OverflowError, ValueError) as error:
        raise ValueError("Границы дня в UTC выходят за допустимый диапазон") from error
    return day


SelectedDay = Annotated[
    date, BeforeValidator(parse_day), AfterValidator(validate_day_range)
]
