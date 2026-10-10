import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.common.schemas import InputModel, Text
from app.modules.commitments.schemas import IntervalOut

Category = Literal["study", "task", "fitness", "break", "recovery", "other"]
_HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"


# ---- What the backend sends to a provider (minimal, no identity or contact data) ----


class DayStats(BaseModel):
    study_minutes: int
    tasks_completed: int
    steps: int
    workout_done: bool


class ContextSleep(BaseModel):
    minutes: int
    quality: int | None = None


class ContextStreak(BaseModel):
    current: int
    active_today: bool


class ContextTask(BaseModel):
    ref: str
    title: str
    priority: str
    due_in_days: int | None
    due_time: str | None = Field(default=None, pattern=_HHMM)
    estimated_minutes: int | None = Field(default=None, ge=1, le=1440)


class ContextExam(BaseModel):
    subject: str
    title: str
    days_left: int


class ContextStudyBlock(BaseModel):
    ref: str = ""
    subject: str
    title: str
    minutes: int
    reason: str


class ContextCommitment(BaseModel):
    title: str
    category: str
    start_minutes: int
    end_minutes: int


class PlanContext(BaseModel):
    planning_start_minutes: int = 480
    planning_end_minutes: int = 1320
    # None keeps older direct-provider test contexts compatible; [] means no capacity.
    free_intervals: list[IntervalOut] | None = None
    commitments: list[ContextCommitment] = Field(default_factory=list)
    date: date
    weekday: str
    current_time: str
    goals: dict[str, int]
    preferred_workout_time: str
    today: DayStats
    yesterday: DayStats
    streaks: dict[str, ContextStreak]
    exams: list[ContextExam]
    study_blocks: list[ContextStudyBlock]
    open_tasks: list[ContextTask]
    note: str | None = None
    account_age_days: int = Field(default=30, description="0 on sign-up day, so 'yesterday' means nothing yet")
    last_night_sleep: ContextSleep | None = None
    omitted_tasks: int = 0


# ---- What a provider must return (validated before it reaches the app) ----


class PlanItem(BaseModel):
    model_config = ConfigDict(extra="forbid")
    start: str = Field(pattern=_HHMM)
    end: str = Field(pattern=_HHMM)
    category: Category
    title: str = Field(min_length=1, max_length=120)
    detail: str | None = Field(default=None, max_length=280)
    task_ref: str | None = Field(default=None, max_length=10)
    study_ref: str | None = Field(default=None, max_length=10)

    @model_validator(mode="after")
    def _end_after_start(self):
        if self.end <= self.start:
            raise ValueError("end must be after start")
        return self


class AIPlanContent(BaseModel):
    model_config = ConfigDict(extra="forbid")
    summary: str = Field(min_length=1, max_length=500)
    items: list[PlanItem] = Field(default_factory=list, max_length=20)
    tips: list[str] = Field(default_factory=list, max_length=5)
    adjustments: list[str] = Field(default_factory=list, max_length=6)

    @field_validator("tips", "adjustments")
    @classmethod
    def _short_lines(cls, lines: list[str]) -> list[str]:
        cleaned = [line.strip() for line in lines if line and line.strip()]
        if any(len(line) > 280 for line in cleaned):
            raise ValueError("each line must be at most 280 characters")
        return cleaned

    @model_validator(mode="after")
    def _sorted_without_overlap(self):
        self.items.sort(key=lambda item: item.start)
        for before, after in zip(self.items, self.items[1:], strict=False):
            if after.start < before.end:
                raise ValueError("plan items overlap")
        return self


# ---- API ----


class DailyPlanRequest(InputModel):
    regenerate: bool = Field(default=False, description="Create a new plan even if one exists for today")
    note: str | None = Field(
        default=None,
        max_length=280,
        description="Optional context for today, e.g. 'slept badly' or 'busy afternoon'",
    )


class ReplanRequest(InputModel):
    request: Text(1000)
    plan_date: date | None = None


class ReplanOperation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: Literal["MOVE", "RESCHEDULE", "SHORTEN", "REMOVE", "ADD", "UNCHANGED"]
    item_key: str
    entity_id: uuid.UUID | None = None
    before: dict | None = None
    after: dict | None = None
    reason: str = Field(min_length=1, max_length=280)


class ReplanDraft(BaseModel):
    model_config = ConfigDict(extra="forbid")
    summary: str = Field(min_length=1, max_length=280)
    explanation: str = Field(min_length=1, max_length=1000)
    items: list[PlanItem] = Field(max_length=20)


class ChatTurn(InputModel):
    role: Literal["user", "assistant"]
    content: Text(2000)


class ChatRequest(InputModel):
    """The question and recent turns. The server builds the user's context itself."""

    message: Text(1000)
    history: list[ChatTurn] = Field(default_factory=list, max_length=10, description="Earlier turns, oldest first")


class ChatReply(BaseModel):
    reply: str
    source: str = Field(description="The provider that answered, e.g. 'ollama'")


class PlanItemOut(BaseModel):
    item_key: str | None = None
    start: str
    end: str
    category: Category
    title: str
    detail: str | None = None
    task_id: uuid.UUID | None = None
    subject_id: uuid.UUID | None = Field(default=None, description="For study items: the subject it belongs to")


class ReplanProposalOut(BaseModel):
    id: uuid.UUID
    base_plan_id: uuid.UUID
    base_revision: int
    plan_date: date
    status: Literal["pending", "applied", "dismissed", "stale", "expired", "invalid"]
    request: str
    summary: str
    explanation: str
    operations: list[ReplanOperation]
    schedule: list[PlanItemOut]
    warnings: list[str]
    validation: dict
    created_at: datetime
    expires_at: datetime
    applied_at: datetime | None = None
    dismissed_at: datetime | None = None


class UnscheduledItem(BaseModel):
    title: str
    category: Literal["task", "study"]
    remaining_minutes: int
    reason: Literal["deadline_passed", "not_scheduled"]
    task_id: uuid.UUID | None = None
    subject_id: uuid.UUID | None = None


class PlanExplanationOut(BaseModel):
    """Server-derived hierarchy from validated items and trusted context."""

    headline: str = Field(max_length=180)
    key_reasons: list[str] = Field(max_length=3)
    supporting_context: list[str] = Field(default_factory=list, max_length=3)


class AIPlanOut(BaseModel):
    id: uuid.UUID
    revision: int = 1
    plan_date: date
    source: str
    is_fallback: bool
    created_at: datetime
    summary: str
    items: list[PlanItemOut]
    tips: list[str]
    adjustments: list[str]
    # Older persisted plans remain readable, but must not claim the new checks.
    planning_start_minutes: int | None = None
    planning_end_minutes: int | None = None
    validation_version: int = 0
    window_start: str | None = None
    window_end: str | None = None
    assumptions: list[str] = Field(default_factory=list)
    unscheduled: list[UnscheduledItem] = Field(default_factory=list)
    explanation: PlanExplanationOut | None = None
