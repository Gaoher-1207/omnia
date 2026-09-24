import uuid
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.activity.models import ActivityDay
from app.modules.activity.schemas import ActivityOut, ActivityUpsert


def get_day(db: Session, user_id: uuid.UUID, day: date) -> ActivityDay | None:
    return db.scalar(select(ActivityDay).where(ActivityDay.user_id == user_id, ActivityDay.day == day))


def get_range(db: Session, user_id: uuid.UUID, start: date, end: date) -> dict[date, ActivityDay]:
    rows = db.scalars(
        select(ActivityDay).where(ActivityDay.user_id == user_id, ActivityDay.day >= start, ActivityDay.day <= end)
    )
    return {row.day: row for row in rows}


def filled_range(db: Session, user_id: uuid.UUID, start: date, end: date) -> list[ActivityOut]:
    """Every day in the range, with zeroed placeholders for days without a record."""
    stored = get_range(db, user_id, start, end)
    out = []
    day = start
    while day <= end:
        row = stored.get(day)
        out.append(ActivityOut.model_validate(row) if row else ActivityOut(day=day))
        day += timedelta(days=1)
    return out


def upsert_day(db: Session, user_id: uuid.UUID, day: date, data: ActivityUpsert) -> ActivityDay:
    """Idempotent: sending the same body twice leaves one row with the same values."""
    row = get_day(db, user_id, day)
    values = data.model_dump()
    if not values["workout_done"]:
        values["workout_minutes"] = 0
        values["workout_type"] = None
    if row is None:
        row = ActivityDay(user_id=user_id, day=day, **values)
        db.add(row)
    else:
        for field, value in values.items():
            setattr(row, field, value)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        row = get_day(db, user_id, day)
        for field, value in values.items():
            setattr(row, field, value)
        db.commit()
    db.refresh(row)
    return row
