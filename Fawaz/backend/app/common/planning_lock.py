"""Serialize planning-state writes with plan creation and proposal application.

PostgreSQL row locks on the owner record provide a portable per-account mutex.
All writes that affect planner context must acquire this lock in their transaction.
"""

import uuid

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.users.models import User


def lock_planning_state(db: Session, user_id: uuid.UUID) -> None:
    db.scalar(select(User.id).where(User.id == user_id).with_for_update())
