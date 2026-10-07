from typing import Annotated

from fastapi import APIRouter, Path

from app.api.dependencies import DatabaseSession
from app.api.schemas import DayResponse, SelectedDay
from app.services.days import get_day

router = APIRouter(prefix="/api/v1/days", tags=["days"])


@router.get(
    "/{date}",
    response_model=DayResponse,
    summary="Получить поездки и сводку за день",
    description=(
        "День определяется началом поездки в Asia/Almaty. Новые поездки сверху, "
        "время в ответе — UTC, деньги — целые тенге (KZT). "
        "Пустой день содержит пустой список и нулевую сводку."
    ),
    response_description="Поездки и финансовая сводка выбранного дня",
)
def read_day(
    date: Annotated[SelectedDay, Path(description="Дата YYYY-MM-DD в Asia/Almaty")],
    session: DatabaseSession,
) -> DayResponse:
    return DayResponse.model_validate(get_day(session, date))
