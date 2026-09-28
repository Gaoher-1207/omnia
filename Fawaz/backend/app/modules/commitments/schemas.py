import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import Field, model_validator

from app.common.schemas import InputModel, ORMModel, Text

CommitmentKind = Literal["recurring", "one_off"]
CommitmentCategory = Literal["college", "work", "class", "coaching", "commute", "appointment", "other"]


class CommitmentInput(InputModel):
    title: Text(80)
    category: CommitmentCategory
    kind: CommitmentKind
    weekdays: list[int] = Field(default_factory=list, max_length=7)
    day: date | None = None
    start_minutes: int = Field(ge=0, le=1438)
    end_minutes: int = Field(ge=1, le=1439)
    enabled: bool = True

    @model_validator(mode="after")
    def _valid_schedule(self):
        if self.start_minutes >= self.end_minutes:
            raise ValueError("End must be after start on the same day")
        if self.kind == "recurring":
            if self.day is not None or not self.weekdays or len(set(self.weekdays)) != len(self.weekdays):
                raise ValueError("Recurring commitments need unique weekdays and no date")
            if any(day < 0 or day > 6 for day in self.weekdays):
                raise ValueError("Weekdays must be Monday=0 through Sunday=6")
        elif self.day is None or self.weekdays:
            raise ValueError("One-off commitments need a date and no weekdays")
        return self


class CommitmentOut(ORMModel):
    id: uuid.UUID
    title: str
    category: CommitmentCategory
    kind: CommitmentKind
    weekdays: list[int]
    day: date | None
    start_minutes: int
    end_minutes: int
    enabled: bool
    created_at: datetime
    updated_at: datetime


class IntervalOut(ORMModel):
    start_minutes: int
    end_minutes: int


class AvailabilityOut(ORMModel):
    day: date
    planning_start_minutes: int
    planning_end_minutes: int
    commitments: list[CommitmentOut]
    busy_intervals: list[IntervalOut]
    free_intervals: list[IntervalOut]
