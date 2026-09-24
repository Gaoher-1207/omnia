import uuid
from datetime import date, time

from pydantic import BaseModel, Field

from app.common.schemas import InputModel, ORMModel


class SleepUpsert(InputModel):
    duration_minutes: int = Field(ge=0, le=1440)
    quality: int | None = Field(default=None, ge=1, le=5, description="1 = awful, 5 = great")
    bedtime: time | None = None
    wake_time: time | None = None


class SleepOut(ORMModel):
    id: uuid.UUID | None = None
    day: date
    duration_minutes: int = 0
    quality: int | None = None
    bedtime: time | None = None
    wake_time: time | None = None
    logged: bool = True


class SleepRange(BaseModel):
    start: date
    end: date
    goal_minutes: int
    average_minutes: int | None
    days: list[SleepOut]
