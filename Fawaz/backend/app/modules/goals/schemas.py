import math
import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import Field, model_validator

from app.common.schemas import InputModel, ORMModel, PatchModel, Text

Category = Literal["study", "tasks", "activity", "sleep", "nutrition", "habits"]


def check_measurement(target: float | None, current: float | None, unit: str | None) -> None:
    """Measurable (positive target, current >= 0, a unit) or completion-only (all three absent)."""
    if target is None:
        if current is not None or unit is not None:
            raise ValueError("A completion-only goal has no current value or unit")
        return
    if not math.isfinite(target) or target <= 0:
        raise ValueError("target_value must be greater than 0")
    if current is None or not math.isfinite(current) or current < 0:
        raise ValueError("A measurable goal needs a current_value of 0 or more")
    if unit is None:
        raise ValueError("A measurable goal needs a unit")


class GoalCreate(InputModel):
    title: Text(120)
    description: str | None = Field(default=None, max_length=500)
    category: Category
    target_value: float | None = Field(default=None, le=1e9)
    current_value: float | None = Field(default=None, le=1e9)
    unit: Text(24) | None = None
    deadline: date | None = None
    completed: bool = False

    @model_validator(mode="after")
    def _measurement(self):
        # A measurable goal may start without a current value: it starts at 0.
        if self.target_value is not None and self.current_value is None:
            self.current_value = 0
        check_measurement(self.target_value, self.current_value, self.unit)
        return self


class GoalUpdate(PatchModel):
    """Omitted fields stay; explicit null clears. Clear target_value, current_value
    and unit together to make a goal completion-only."""

    non_nullable = frozenset({"title", "category", "completed"})

    title: Text(120) | None = None
    description: str | None = Field(default=None, max_length=500)
    category: Category | None = None
    target_value: float | None = Field(default=None, le=1e9)
    current_value: float | None = Field(default=None, le=1e9)
    unit: Text(24) | None = None
    deadline: date | None = None
    completed: bool | None = None


class GoalOut(ORMModel):
    id: uuid.UUID
    title: str
    description: str | None
    category: Category
    target_value: float | None
    current_value: float | None
    unit: str | None
    deadline: date | None
    completed: bool
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime
