"""Manual commitment CRUD and deterministic same-day interval subtraction."""

import uuid
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.ownership import get_owned
from app.modules.commitments.models import Commitment
from app.modules.commitments.schemas import CommitmentInput, IntervalOut


def list_owned(db: Session, user_id: uuid.UUID) -> list[Commitment]:
    return list(db.scalars(select(Commitment).where(Commitment.user_id == user_id).order_by(Commitment.created_at)))


def for_day(rows: list[Commitment], day: date) -> list[Commitment]:
    return [
        row
        for row in rows
        if row.enabled
        and (
            (row.kind == "one_off" and row.day == day)
            or (row.kind == "recurring" and day.weekday() in row.weekdays)
        )
    ]


def free_intervals(start: int, end: int, busy: list[tuple[int, int]]) -> tuple[list[IntervalOut], list[IntervalOut]]:
    """Clip, merge overlap/adjacency, then subtract from [start, end)."""
    merged: list[list[int]] = []
    for left, right in sorted((max(start, a), min(end, b)) for a, b in busy if a < end and b > start):
        if left >= right:
            continue
        if merged and left <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], right)
        else:
            merged.append([left, right])
    free = []
    cursor = start
    for left, right in merged:
        if cursor < left:
            free.append(IntervalOut(start_minutes=cursor, end_minutes=left))
        cursor = right
    if cursor < end:
        free.append(IntervalOut(start_minutes=cursor, end_minutes=end))
    return (
        [IntervalOut(start_minutes=a, end_minutes=b) for a, b in merged],
        free,
    )


def availability(db: Session, user_id: uuid.UUID, day: date, start: int, end: int):
    applicable = for_day(list_owned(db, user_id), day)
    busy, free = free_intervals(start, end, [(row.start_minutes, row.end_minutes) for row in applicable])
    return applicable, busy, free


def save(db: Session, user_id: uuid.UUID, body: CommitmentInput, commitment_id: uuid.UUID | None = None) -> Commitment:
    row = (
        get_owned(db, Commitment, commitment_id, user_id, "Commitment")
        if commitment_id
        else Commitment(user_id=user_id)
    )
    for key, value in body.model_dump().items():
        setattr(row, key, value)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def delete(db: Session, user_id: uuid.UUID, commitment_id: uuid.UUID) -> None:
    row = get_owned(db, Commitment, commitment_id, user_id, "Commitment")
    db.delete(row)
    db.commit()
