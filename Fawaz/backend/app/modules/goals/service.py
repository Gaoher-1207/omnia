import uuid

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.common.ownership import get_owned
from app.core.errors import AppError
from app.core.time import utcnow
from app.modules.goals.models import Goal
from app.modules.goals.schemas import GoalCreate, GoalUpdate, check_measurement

MAX_GOALS = 200


class GoalValidationError(AppError):
    status_code = 422
    code = "validation_error"


def list_goals(db: Session, user_id: uuid.UUID) -> list[Goal]:
    # Open goals first, then nearest deadline (none last), then newest.
    return list(
        db.scalars(
            select(Goal)
            .where(Goal.user_id == user_id)
            .order_by(Goal.completed, Goal.deadline.is_(None), Goal.deadline, Goal.created_at.desc())
        )
    )


def create_goal(db: Session, user_id: uuid.UUID, data: GoalCreate) -> Goal:
    count = db.scalar(select(func.count()).select_from(Goal).where(Goal.user_id == user_id))
    if count >= MAX_GOALS:
        raise GoalValidationError(f"You can keep up to {MAX_GOALS} goals.")
    goal = Goal(user_id=user_id, **data.model_dump())
    if goal.completed:
        goal.completed_at = utcnow()
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return goal


def update_goal(db: Session, user_id: uuid.UUID, goal_id: uuid.UUID, data: GoalUpdate) -> Goal:
    goal = get_owned(db, Goal, goal_id, user_id, "Goal")
    changes = data.changes()
    target = changes.get("target_value", goal.target_value)
    current = changes.get("current_value", goal.current_value)
    unit = changes.get("unit", goal.unit)
    # Becoming measurable without a value starts at 0, as on creation.
    if target is not None and current is None and "current_value" not in changes:
        current = 0
    try:
        check_measurement(target, current, unit)
    except ValueError as exc:
        raise GoalValidationError(str(exc)) from None
    if "completed" in changes and changes["completed"] != goal.completed:
        # Completion is a decision; it never touches the recorded values.
        goal.completed_at = utcnow() if changes["completed"] else None
    for field, value in changes.items():
        setattr(goal, field, value)
    goal.target_value, goal.current_value, goal.unit = target, current, unit
    db.commit()
    db.refresh(goal)
    return goal


def delete_goal(db: Session, user_id: uuid.UUID, goal_id: uuid.UUID) -> None:
    goal = get_owned(db, Goal, goal_id, user_id, "Goal")
    db.delete(goal)
    db.commit()
