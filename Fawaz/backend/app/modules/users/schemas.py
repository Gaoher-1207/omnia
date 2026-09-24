import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import Field, StringConstraints, field_validator

from app.common.schemas import ORMModel, PatchModel, Text
from app.core.time import normalize_timezone

WorkoutTime = Literal["morning", "afternoon", "evening"]
Username = Annotated[str, StringConstraints(pattern=r"^[a-z0-9_]{3,30}$")]


def check_timezone(value: str | None) -> str | None:
    if value is None:
        return None
    canonical = normalize_timezone(value)
    if canonical is None:
        raise ValueError("Unknown timezone. Use an IANA name such as 'Asia/Kolkata'.")
    return canonical


class ProfileOut(ORMModel):
    display_name: str
    timezone: str
    daily_study_goal_minutes: int
    daily_step_goal: int
    daily_task_goal: int
    preferred_workout_time: WorkoutTime
    daily_sleep_goal_minutes: int
    daily_calorie_goal: int
    username: str | None


class UserOut(ORMModel):
    id: uuid.UUID
    email: str
    created_at: datetime
    profile: ProfileOut


class ProfileUpdate(PatchModel):
    non_nullable = frozenset(
        {
            "display_name",
            "timezone",
            "daily_study_goal_minutes",
            "daily_step_goal",
            "daily_task_goal",
            "preferred_workout_time",
            "daily_sleep_goal_minutes",
            "daily_calorie_goal",
        }
    )

    display_name: Text(60) | None = None
    timezone: str | None = Field(default=None, max_length=64)
    daily_study_goal_minutes: int | None = Field(default=None, ge=0, le=960)
    daily_step_goal: int | None = Field(default=None, ge=0, le=100000)
    daily_task_goal: int | None = Field(default=None, ge=0, le=50)
    preferred_workout_time: WorkoutTime | None = None
    daily_sleep_goal_minutes: int | None = Field(default=None, ge=0, le=960)
    daily_calorie_goal: int | None = Field(default=None, ge=0, le=10000)
    username: Username | None = Field(
        default=None, description="3–30 lowercase letters, digits or _. Friends find you by it."
    )

    _tz = field_validator("timezone")(check_timezone)

    @field_validator("username", mode="before")
    @classmethod
    def _normalize_username(cls, value):
        return value.strip().lower() if isinstance(value, str) else value
