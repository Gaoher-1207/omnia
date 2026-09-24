import uuid
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.sleep.models import SleepLog
from app.modules.sleep.schemas import SleepOut, SleepUpsert


def get_day(db: Session, user_id: uuid.UUID, day: date) -> SleepLog | None:
    return db.scalar(select(SleepLog).where(SleepLog.user_id == user_id, SleepLog.day == day))


def get_range(db: Session, user_id: uuid.UUID, start: date, end: date) -> dict[date, SleepLog]:
    rows = db.scalars(select(SleepLog).where(SleepLog.user_id == user_id, SleepLog.day >= start, SleepLog.day <= end))
    return {row.day: row for row in rows}


def filled_range(db: Session, user_id: uuid.UUID, start: date, end: date) -> list[SleepOut]:
    stored = get_range(db, user_id, start, end)
    out, day = [], start
    while day <= end:
        row = stored.get(day)
        out.append(SleepOut.model_validate(row) if row else SleepOut(day=day, logged=False))
        day += timedelta(days=1)
    return out


def upsert_day(db: Session, user_id: uuid.UUID, day: date, data: SleepUpsert) -> SleepLog:
    values = data.model_dump()
    row = get_day(db, user_id, day)
    if row is None:
        row = SleepLog(user_id=user_id, day=day, **values)
        db.add(row)
    else:
        for field, value in values.items():
            setattr(row, field, value)
    try:
        db.commit()
    except IntegrityError:  # two first-time saves raced; apply to the winner
        db.rollback()
        row = get_day(db, user_id, day)
        for field, value in values.items():
            setattr(row, field, value)
        db.commit()
    db.refresh(row)
    return row
