from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy.orm import Session, sessionmaker

from app.api.days import router as days_router
from app.api.health import router as health_router
from app.api.trips import router as trips_router
from app.core.config import get_settings
from app.db.database import create_database_engine


@asynccontextmanager
async def lifespan(application: FastAPI) -> AsyncIterator[None]:
    engine = create_database_engine(get_settings().database_url)
    application.state.session_factory = sessionmaker(
        bind=engine, class_=Session, expire_on_commit=False
    )
    try:
        yield
    finally:
        engine.dispose()


def create_app() -> FastAPI:
    application = FastAPI(
        title="Дневник смен водителя", version="0.1.0", lifespan=lifespan
    )
    application.include_router(health_router)
    application.include_router(days_router)
    application.include_router(trips_router)
    return application


app = create_app()
