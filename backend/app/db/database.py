from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.core.config import get_settings


class Base(DeclarativeBase):
    pass


def create_database_engine(database_url: str) -> Engine:
    return create_engine(database_url, connect_args={"check_same_thread": False})


engine = create_database_engine(get_settings().database_url)
SessionFactory = sessionmaker(bind=engine, class_=Session, expire_on_commit=False)
