import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.common.schemas import HexColor, InputModel, ORMModel, PatchModel, Text

BacklogKind = Literal["backlog", "revision"]
BacklogStatus = Literal["pending", "done"]


# Subjects
class SubjectCreate(InputModel):
    name: Text(60)
    color: HexColor | None = None


class SubjectUpdate(PatchModel):
    non_nullable = frozenset({"name"})

    name: Text(60) | None = None
    color: HexColor | None = None


class SubjectOut(ORMModel):
    id: uuid.UUID
    name: str
    color: str | None
    created_at: datetime


class SubjectRef(ORMModel):
    id: uuid.UUID
    name: str
    color: str | None


# Exams
class ExamCreate(InputModel):
    subject_id: uuid.UUID
    title: Text(120)
    exam_date: date
    notes: str | None = Field(default=None, max_length=2000)


class ExamUpdate(PatchModel):
    non_nullable = frozenset({"subject_id", "title", "exam_date"})

    subject_id: uuid.UUID | None = None
    title: Text(120) | None = None
    exam_date: date | None = None
    notes: str | None = Field(default=None, max_length=2000)


class ExamOut(ORMModel):
    id: uuid.UUID
    title: str
    exam_date: date
    notes: str | None
    subject: SubjectRef
    days_left: int = 0


# Backlog / revision items
class BacklogCreate(InputModel):
    subject_id: uuid.UUID
    title: Text(200)
    kind: BacklogKind = "backlog"
    estimated_minutes: int = Field(default=60, ge=5, le=600)


class BacklogUpdate(PatchModel):
    non_nullable = frozenset({"subject_id", "title", "kind", "status", "estimated_minutes"})

    subject_id: uuid.UUID | None = None
    title: Text(200) | None = None
    kind: BacklogKind | None = None
    status: BacklogStatus | None = None
    estimated_minutes: int | None = Field(default=None, ge=5, le=600)


class BacklogOut(ORMModel):
    id: uuid.UUID
    title: str
    kind: BacklogKind
    status: BacklogStatus
    estimated_minutes: int
    completed_at: datetime | None
    created_at: datetime
    subject: SubjectRef


# Study sessions
class SessionCreate(InputModel):
    duration_minutes: int = Field(ge=1, le=720)
    subject_id: uuid.UUID | None = None
    backlog_item_id: uuid.UUID | None = None
    session_date: date | None = Field(default=None, description="Defaults to today in your timezone")
    notes: str | None = Field(default=None, max_length=2000)
    complete_backlog_item: bool = Field(default=False, description="Mark the linked backlog item as done")


class SessionOut(ORMModel):
    id: uuid.UUID
    session_date: date
    duration_minutes: int
    notes: str | None
    backlog_item_id: uuid.UUID | None
    subject: SubjectRef | None
    created_at: datetime


# Plan
class PlanBlock(BaseModel):
    subject_id: uuid.UUID
    subject_name: str
    backlog_item_id: uuid.UUID | None
    title: str
    minutes: int
    reason: str


class PlanExam(BaseModel):
    exam_id: uuid.UUID
    subject_name: str
    title: str


class PlanDay(BaseModel):
    date: date
    available_minutes: int
    planned_minutes: int
    blocks: list[PlanBlock]
    exams: list[PlanExam]


class StudyPlanOut(BaseModel):
    start_date: date
    days: list[PlanDay]
    unscheduled_minutes: int
    warnings: list[str]
