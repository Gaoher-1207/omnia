import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Query, Response, status

from app.common.deps import CurrentUser, DbSession
from app.core.errors import AppError
from app.core.time import local_today
from app.modules.study import service
from app.modules.study.schemas import (
    BacklogCreate,
    BacklogOut,
    BacklogStatus,
    BacklogUpdate,
    ExamCreate,
    ExamOut,
    ExamUpdate,
    SessionCreate,
    SessionOut,
    StudyPlanOut,
    SubjectCreate,
    SubjectOut,
    SubjectUpdate,
)

router = APIRouter(prefix="/study", tags=["study"])
_NO_CONTENT = status.HTTP_204_NO_CONTENT


# Subjects
@router.get("/subjects", response_model=list[SubjectOut], summary="List my subjects")
def list_subjects(user: CurrentUser, db: DbSession):
    return service.list_subjects(db, user.id)


@router.post("/subjects", response_model=SubjectOut, status_code=201, summary="Add a subject")
def create_subject(body: SubjectCreate, user: CurrentUser, db: DbSession):
    return service.create_subject(db, user.id, body)


@router.patch("/subjects/{subject_id}", response_model=SubjectOut, summary="Rename or recolor a subject")
def update_subject(subject_id: uuid.UUID, body: SubjectUpdate, user: CurrentUser, db: DbSession):
    return service.update_subject(db, user.id, subject_id, body)


@router.delete(
    "/subjects/{subject_id}",
    status_code=_NO_CONTENT,
    summary="Delete a subject with its exams and backlog (sessions are kept, unlinked)",
)
def delete_subject(subject_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_subject(db, user.id, subject_id)
    return Response(status_code=_NO_CONTENT)


# Exams
@router.get("/exams", response_model=list[ExamOut], summary="List my exams (upcoming by default)")
def list_exams(user: CurrentUser, db: DbSession, include_past: bool = False):
    today = local_today(user.profile.timezone)
    exams = service.list_exams(db, user.id, include_past=include_past, today=today)
    return [service.exam_out(e, today) for e in exams]


@router.post("/exams", response_model=ExamOut, status_code=201, summary="Add an exam")
def create_exam(body: ExamCreate, user: CurrentUser, db: DbSession):
    exam = service.create_exam(db, user.id, body)
    return service.exam_out(exam, local_today(user.profile.timezone))


@router.patch("/exams/{exam_id}", response_model=ExamOut, summary="Update an exam")
def update_exam(exam_id: uuid.UUID, body: ExamUpdate, user: CurrentUser, db: DbSession):
    exam = service.update_exam(db, user.id, exam_id, body)
    return service.exam_out(exam, local_today(user.profile.timezone))


@router.delete("/exams/{exam_id}", status_code=_NO_CONTENT, summary="Delete an exam")
def delete_exam(exam_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_exam(db, user.id, exam_id)
    return Response(status_code=_NO_CONTENT)


# Backlog
@router.get("/backlog", response_model=list[BacklogOut], summary="List backlog and revision items")
def list_backlog(
    user: CurrentUser,
    db: DbSession,
    status_filter: BacklogStatus | None = Query(default=None, alias="status"),
    subject_id: uuid.UUID | None = None,
):
    return service.list_backlog(db, user.id, status=status_filter, subject_id=subject_id)


@router.post("/backlog", response_model=BacklogOut, status_code=201, summary="Add a backlog or revision item")
def create_backlog_item(body: BacklogCreate, user: CurrentUser, db: DbSession):
    return service.create_backlog_item(db, user.id, body)


@router.patch("/backlog/{item_id}", response_model=BacklogOut, summary="Update or complete a backlog item")
def update_backlog_item(item_id: uuid.UUID, body: BacklogUpdate, user: CurrentUser, db: DbSession):
    return service.update_backlog_item(db, user.id, item_id, body)


@router.delete("/backlog/{item_id}", status_code=_NO_CONTENT, summary="Delete a backlog item")
def delete_backlog_item(item_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_backlog_item(db, user.id, item_id)
    return Response(status_code=_NO_CONTENT)


# Sessions
@router.get("/sessions", response_model=list[SessionOut], summary="List study sessions in a date range")
def list_sessions(
    user: CurrentUser,
    db: DbSession,
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
):
    today = local_today(user.profile.timezone)
    end = end or today
    start = start or end - timedelta(days=13)
    if start > end:
        raise AppError("'from' must be on or before 'to'")
    if (end - start).days > 366:
        raise AppError("Date range can be at most one year")
    return service.list_sessions(db, user.id, start=start, end=end)


@router.post("/sessions", response_model=SessionOut, status_code=201, summary="Log a study session")
def create_session(body: SessionCreate, user: CurrentUser, db: DbSession):
    return service.create_session(db, user, body)


@router.delete("/sessions/{session_id}", status_code=_NO_CONTENT, summary="Delete a study session")
def delete_session(session_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_session(db, user.id, session_id)
    return Response(status_code=_NO_CONTENT)


# Plan
@router.get("/plan", response_model=StudyPlanOut, summary="Study plan for the next few days")
def study_plan(user: CurrentUser, db: DbSession, days: int = Query(default=7, ge=1, le=28)):
    return service.study_plan(db, user, days)
