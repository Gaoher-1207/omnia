"""Study time from plan blocks marked done, never counted twice.

A study block marked **done** is credited as a study session (`source="plan"`) for
its subject, on the plan's date, for its planned length. A block marked **partly
done** is credited only for the minutes the user gave; without minutes it earns
nothing. Skipped, cleared and untouched blocks earn nothing, and so does every
block that isn't a study block.

Focus phases are logged separately (`source="focus"`, with `started_at`). Any of
those minutes that fall inside the block's time are already study time, so the
block is credited only for the rest. Credits are recomputed whenever the block's
outcome or a Focus session on that date changes, so the order of the two never
matters and repeated requests never add up.
"""

import uuid
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.ai.constraints import minutes
from app.modules.ai.models import PlanItemOutcome
from app.modules.study.models import StudySession, Subject

MAX_SESSION_MINUTES = 720


def _block_window(outcome: PlanItemOutcome, tz: str) -> tuple[datetime, datetime]:
    zone = ZoneInfo(tz)
    day = datetime.combine(outcome.plan_date, datetime.min.time(), tzinfo=zone)
    return day + timedelta(minutes=minutes(outcome.start)), day + timedelta(minutes=minutes(outcome.end))


def target_minutes(outcome: PlanItemOutcome) -> int:
    """Study minutes this outcome stands for, before any Focus overlap."""
    if outcome.category != "study":
        return 0
    if outcome.status == "done":
        return minutes(outcome.end) - minutes(outcome.start)
    if outcome.status == "partial":
        return outcome.minutes or 0
    return 0


def _focus_overlap(db: Session, user_id: uuid.UUID, outcome: PlanItemOutcome, tz: str) -> int:
    start, end = _block_window(outcome, tz)
    total = 0
    for session in db.scalars(
        select(StudySession).where(
            StudySession.user_id == user_id,
            StudySession.source == "focus",
            StudySession.started_at.is_not(None),
            StudySession.session_date.between(
                outcome.plan_date - timedelta(days=1), outcome.plan_date + timedelta(days=1)
            ),
        )
    ):
        focus_start = session.started_at
        focus_end = focus_start + timedelta(minutes=session.duration_minutes)
        overlap = (min(end, focus_end) - max(start, focus_start)).total_seconds()
        if overlap > 0:
            total += int(overlap // 60)
    return total


def sync_credit(db: Session, user_id: uuid.UUID, tz: str, outcome: PlanItemOutcome) -> None:
    """Make the outcome's credited session match what it should be now. No commit."""
    credit = max(0, target_minutes(outcome) - _focus_overlap(db, user_id, outcome, tz))
    session = db.get(StudySession, outcome.study_session_id) if outcome.study_session_id else None
    if session is not None and session.user_id != user_id:  # never touch another account's row
        session = None
    if credit == 0:
        if session is not None:
            db.delete(session)
        outcome.study_session_id = None
        return
    subject_id = outcome.subject_id
    if (
        subject_id is not None
        and db.scalar(select(Subject.id).where(Subject.id == subject_id, Subject.user_id == user_id)) is None
    ):
        subject_id = None  # the subject was deleted since the plan was made
    if session is None:
        session = StudySession(user_id=user_id, source="plan")
        db.add(session)
    session.subject_id = subject_id
    session.session_date = outcome.plan_date
    session.duration_minutes = min(credit, MAX_SESSION_MINUTES)
    session.notes = f"Planned block: {outcome.title}"[:2000]
    db.flush()  # the session row must exist before the outcome points at it
    outcome.study_session_id = session.id


def remove_credit(db: Session, user_id: uuid.UUID, outcome: PlanItemOutcome) -> None:
    if outcome.study_session_id is None:
        return
    session = db.get(StudySession, outcome.study_session_id)
    if session is not None and session.user_id == user_id:
        db.delete(session)
    outcome.study_session_id = None


def resync_day(db: Session, user_id: uuid.UUID, tz: str, day: date) -> None:
    """Recompute every study credit on and around `day` after Focus time changed. No commit."""
    for outcome in db.scalars(
        select(PlanItemOutcome).where(
            PlanItemOutcome.user_id == user_id,
            PlanItemOutcome.category == "study",
            PlanItemOutcome.plan_date.between(day - timedelta(days=1), day + timedelta(days=1)),
        )
    ):
        sync_credit(db, user_id, tz, outcome)
