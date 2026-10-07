from fastapi import APIRouter, HTTPException, Response, status

from app.api.dependencies import DatabaseSession
from app.api.schemas import ConflictResponse, TripCreate
from app.domain.trips import TripConflictError, TripData
from app.services.trips import add_trip

router = APIRouter(prefix="/api/v1/trips", tags=["trips"])


@router.post(
    "",
    response_model=TripData,
    status_code=status.HTTP_201_CREATED,
    summary="Добавить поездку или повторить отправку",
    description=(
        "ID определяет поездку. Повтор с теми же нормализованными данными "
        "возвращает существующую поездку; другие данные того же ID — конфликт. "
        "Равные моменты с разными часовыми смещениями считаются равными. "
        "Время в ответе — UTC, деньги — целые тенге (KZT)."
    ),
    response_description="Созданная и сохранённая поездка",
    responses={
        200: {"model": TripData, "description": "Повтор: существующая поездка"},
        409: {"model": ConflictResponse, "description": "ID занят другими данными"},
    },
)
def create_trip(
    trip: TripCreate, response: Response, session: DatabaseSession
) -> TripData:
    try:
        result = add_trip(session, TripData.model_validate(trip.model_dump()))
    except TripConflictError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(error)
        ) from error
    if not result.created:
        response.status_code = status.HTTP_200_OK
    return result.trip
