import uuid
from datetime import date, datetime, time
from typing import Literal

from pydantic import Field, model_validator

from app.common.schemas import InputModel, ORMModel, PatchModel, Text

Priority = Literal["low", "medium", "high"]
TaskStatus = Literal["todo", "done"]
Category = Literal["study", "tasks", "activity", "sleep", "nutrition", "habits"]


class TaskCreate(InputModel):
    title: Text(200)
    notes: str | None = Field(default=None, max_length=2000)
    priority: Priority = "medium"
    due_date: date | None = None
    due_time: time | None = Field(default=None, description="Local time on due_date; needs due_date")
    estimated_minutes: int | None = Field(default=None, ge=1, le=1440)
    category: Category = "tasks"

    @model_validator(mode="after")
    def _time_needs_date(self):
        if self.due_time is not None and self.due_date is None:
            raise ValueError("due_time needs a due_date")
        return self


class TaskUpdate(PatchModel):
    non_nullable = frozenset({"title", "priority", "status", "category"})

    title: Text(200) | None = None
    notes: str | None = Field(default=None, max_length=2000)
    priority: Priority | None = None
    status: TaskStatus | None = None
    due_date: date | None = None
    due_time: time | None = None
    estimated_minutes: int | None = Field(default=None, ge=1, le=1440)
    category: Category | None = None


class TaskOut(ORMModel):
    id: uuid.UUID
    title: str
    notes: str | None
    priority: Priority
    status: TaskStatus
    due_date: date | None
    due_time: time | None
    estimated_minutes: int | None
    category: Category
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime
