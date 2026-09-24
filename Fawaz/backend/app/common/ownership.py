"""Ownership checks.

The user id always comes from the verified token, never from the request body.
A resource that belongs to someone else is reported as "not found" so that ids
can't be probed to learn what exists.
"""

import uuid
from typing import TypeVar

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.errors import NotFoundError

M = TypeVar("M")


def get_owned(db: Session, model: type[M], resource_id: uuid.UUID, user_id: uuid.UUID, label: str) -> M:
    obj = db.scalar(select(model).where(model.id == resource_id, model.user_id == user_id))
    if obj is None:
        raise NotFoundError(label)
    return obj
