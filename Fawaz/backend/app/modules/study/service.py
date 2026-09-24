import uuid
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.common.ownership import get_owned
from app.core.errors import AppError, ConflictError
from app.core.time import local_today, utcnow
from app.modules.study.models import BacklogItem, Exam, StudySession, Subject
from app.modules.study.planner import PlannerExam, PlannerItem, build_study_plan
from app.modules.study.schemas import (
    BacklogCreate,
    BacklogUpdate,
    ExamCreate,
    ExamOut,
    ExamUpdate,
    SessionCreate,
    StudyPlanOut,
    SubjectCreate,
    SubjectUpdate,
)
from app.modules.users.models import User


class StudyInputError(AppError):
    status_code = 422
    code = "validation_error"


# Subjects


def list_subjects(db: Session, user_id: uuid.UUID) -> list[Subject]:
    return list(db.scalars(select(Subject).where(Subject.user_id == user_id).order_by(Subject.name)))


def create_subject(db: Session, user_id: uuid.UUID, data: SubjectCreate) -> Subject:
    subject = Subject(user_id=user_id, **data.model_dump())
    db.add(subject)
    _commit_unique_subject(db)
    db.refresh(subject)
    return subject


def update_subject(db: Session, user_id: uuid.UUID, subject_id: uuid.UUID, data: SubjectUpdate) -> Subject:
    subject = get_owned(db, Subject, subject_id, user_id, "Subject")
    for field, value in data.changes().items():
        setattr(subject, field, value)
    _commit_unique_subject(db)
    db.refresh(subject)
    return subject


def delete_subject(db: Session, user_id: uuid.UUID, subject_id: uuid.UUID) -> None:
    subject = get_owned(db, Subject, subject_id, user_id, "Subject")
    db.delete(subject)
    db.commit()


def _commit_unique_subject(db: Session) -> None:
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ConflictError("You already have a subject with this name") from None


# Exams


def exam_out(exam: Exam, today: date) -> ExamOut:
    out = ExamOut.model_validate(exam)
    out.days_left = (exam.exam_date - today).days
    return out


def list_exams(db: Session, user_id: uuid.UUID, *, include_past: bool, today: date) -> list[Exam]:
    query = select(Exam).where(Exam.user_id == user_id)
    if not include_past:
        query = query.where(Exam.exam_date >= today)
    return list(db.scalars(query.order_by(Exam.exam_date)))


def create_exam(db: Session, user_id: uuid.UUID, data: ExamCreate) -> Exam:
    get_owned(db, Subject, data.subject_id, user_id, "Subject")
    exam = Exam(user_id=user_id, **data.model_dump())
    db.add(exam)
    db.commit()
    db.refresh(exam)
    return exam


def update_exam(db: Session, user_id: uuid.UUID, exam_id: uuid.UUID, data: ExamUpdate) -> Exam:
    exam = get_owned(db, Exam, exam_id, user_id, "Exam")
    changes = data.changes()
    if "subject_id" in changes:
        get_owned(db, Subject, changes["subject_id"], user_id, "Subject")
    for field, value in changes.items():
        setattr(exam, field, value)
    db.commit()
    db.refresh(exam)
    return exam


def delete_exam(db: Session, user_id: uuid.UUID, exam_id: uuid.UUID) -> None:
    exam = get_owned(db, Exam, exam_id, user_id, "Exam")
    db.delete(exam)
    db.commit()


# Backlog


def list_backlog(
    db: Session, user_id: uuid.UUID, *, status: str | None, subject_id: uuid.UUID | None
) -> list[BacklogItem]:
    query = select(BacklogItem).where(BacklogItem.user_id == user_id)
    if status:
        query = query.where(BacklogItem.status == status)
    if subject_id:
        query = query.where(BacklogItem.subject_id == subject_id)
    return list(db.scalars(query.order_by(BacklogItem.status.desc(), BacklogItem.created_at)))


def create_backlog_item(db: Session, user_id: uuid.UUID, data: BacklogCreate) -> BacklogItem:
    get_owned(db, Subject, data.subject_id, user_id, "Subject")
    item = BacklogItem(user_id=user_id, **data.model_dump())
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def update_backlog_item(db: Session, user_id: uuid.UUID, item_id: uuid.UUID, data: BacklogUpdate) -> BacklogItem:
    item = get_owned(db, BacklogItem, item_id, user_id, "Backlog item")
    changes = data.changes()
    if "subject_id" in changes:
        get_owned(db, Subject, changes["subject_id"], user_id, "Subject")
    if changes.get("status") == "done" and item.status != "done":
        item.completed_at = utcnow()
    elif changes.get("status") == "pending":
        item.completed_at = None
    for field, value in changes.items():
        setattr(item, field, value)
    db.commit()
    db.refresh(item)
    return item


def delete_backlog_item(db: Session, user_id: uuid.UUID, item_id: uuid.UUID) -> None:
    item = get_owned(db, BacklogItem, item_id, user_id, "Backlog item")
    db.delete(item)
    db.commit()


# Sessions


def list_sessions(db: Session, user_id: uuid.UUID, *, start: date, end: date) -> list[StudySession]:
    return list(
        db.scalars(
            select(StudySession)
            .where(
                StudySession.user_id == user_id,
                StudySession.session_date >= start,
                StudySession.session_date <= end,
            )
            .order_by(StudySession.session_date.desc(), StudySession.created_at.desc())
        )
    )


def create_session(db: Session, user: User, data: SessionCreate) -> StudySession:
    today = local_today(user.profile.timezone)
    session_date = data.session_date or today
    if session_date > today:
        raise StudyInputError(
            "Study sessions can't be logged for a future date",
            details=[{"field": "body.session_date", "message": "Date is in the future"}],
        )
    subject_id = data.subject_id
    item = None
    if data.backlog_item_id:
        item = get_owned(db, BacklogItem, data.backlog_item_id, user.id, "Backlog item")
        if subject_id is None:
            subject_id = item.subject_id
        elif subject_id != item.subject_id:
            raise StudyInputError(
                "The backlog item belongs to a different subject",
                details=[{"field": "body.subject_id", "message": "Does not match the backlog item"}],
            )
    if subject_id:
        get_owned(db, Subject, subject_id, user.id, "Subject")
    session = StudySession(
        user_id=user.id,
        subject_id=subject_id,
        backlog_item_id=data.backlog_item_id,
        session_date=session_date,
        duration_minutes=data.duration_minutes,
        notes=data.notes,
    )
    db.add(session)
    if item is not None and data.complete_backlog_item and item.status != "done":
        item.status = "done"
        item.completed_at = utcnow()
    db.commit()
    db.refresh(session)
    return session


def delete_session(db: Session, user_id: uuid.UUID, session_id: uuid.UUID) -> None:
    session = get_owned(db, StudySession, session_id, user_id, "Study session")
    db.delete(session)
    db.commit()


def minutes_by_day(db: Session, user_id: uuid.UUID, start: date, end: date) -> dict[date, int]:
    rows = db.execute(
        select(StudySession.session_date, func.sum(StudySession.duration_minutes))
        .where(
            StudySession.user_id == user_id,
            StudySession.session_date >= start,
            StudySession.session_date <= end,
        )
        .group_by(StudySession.session_date)
    )
    return {day: int(total or 0) for day, total in rows}


# Plan


def study_plan(db: Session, user: User, days: int) -> StudyPlanOut:
    profile = user.profile
    today = local_today(profile.timezone)
    subjects = {s.id: s.name for s in list_subjects(db, user.id)}
    exams = [
        PlannerExam(id=e.id, subject_id=e.subject_id, title=e.title, exam_date=e.exam_date)
        for e in list_exams(db, user.id, include_past=False, today=today)
    ]
    items = [
        PlannerItem(
            id=i.id,
            subject_id=i.subject_id,
            title=i.title,
            kind=i.kind,
            minutes=i.estimated_minutes,
            order=n,
        )
        for n, i in enumerate(list_backlog(db, user.id, status="pending", subject_id=None))
    ]
    studied_today = minutes_by_day(db, user.id, today, today).get(today, 0)
    return build_study_plan(
        start=today,
        days=days,
        daily_minutes=profile.daily_study_goal_minutes,
        studied_today=studied_today,
        subjects=subjects,
        exams=exams,
        items=items,
    )


def history_window(today: date, days: int) -> tuple[date, date]:
    return today - timedelta(days=days - 1), today
