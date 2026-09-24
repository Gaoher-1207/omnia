import uuid
from datetime import date, datetime

from pydantic import BaseModel, Field

from app.common.schemas import InputModel, ORMModel, Text


class ActivityUpsert(InputModel):
    steps: int = Field(default=0, ge=0, le=200000)
    workout_done: bool = False
    workout_minutes: int = Field(default=0, ge=0, le=600)
    workout_type: Text(40) | None = None


class ActivityOut(ORMModel):
    id: uuid.UUID | None = None
    day: date
    steps: int = 0
    workout_done: bool = False
    workout_minutes: int = 0
    workout_type: str | None = None
    updated_at: datetime | None = None


class ActivityRange(BaseModel):
    start: date
    end: date
    step_goal: int
    days: list[ActivityOut]
