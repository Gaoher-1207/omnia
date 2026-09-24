import uuid
from datetime import date

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.common.ownership import get_owned
from app.core.time import utcnow
from app.modules.tasks.models import Task
from app.modules.tasks.schemas import TaskCreate, TaskUpdate

_PRIORITY_RANK = case({"high": 0, "medium": 1, "low": 2}, value=Task.priority, else_=3)


def list_tasks(
    db: Session,
    user_id: uuid.UUID,
    *,
    status: str | None,
    priority: str | None,
    due_on_or_before: date | None,
    limit: int,
    offset: int,
) -> tuple[list[Task], int]:
    query = select(Task).where(Task.user_id == user_id)
    if status:
        query = query.where(Task.status == status)
    if priority:
        query = query.where(Task.priority == priority)
    if due_on_or_before:
        query = query.where(Task.due_date.is_not(None), Task.due_date <= due_on_or_before)
    total = db.scalar(select(func.count()).select_from(query.subquery())) or 0
    ordered = query.order_by(
        case((Task.status == "todo", 0), else_=1),
        case((Task.due_date.is_(None), 1), else_=0),
        Task.due_date,
        case((Task.due_time.is_(None), 1), else_=0),
        Task.due_time,
        _PRIORITY_RANK,
        Task.created_at.desc(),
    )
    return list(db.scalars(ordered.limit(limit).offset(offset))), total


def open_tasks_for_planning(db: Session, user_id: uuid.UUID, limit: int = 10) -> list[Task]:
    items, _ = list_tasks(db, user_id, status="todo", priority=None, due_on_or_before=None, limit=limit, offset=0)
    return items


def create_task(db: Session, user_id: uuid.UUID, data: TaskCreate) -> Task:
    task = Task(user_id=user_id, **data.model_dump())
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


def update_task(db: Session, user_id: uuid.UUID, task_id: uuid.UUID, data: TaskUpdate) -> Task:
    task = get_owned(db, Task, task_id, user_id, "Task")
    changes = data.changes()
    new_status = changes.get("status")
    if new_status == "done" and task.status != "done":
        task.completed_at = utcnow()
    elif new_status == "todo":
        task.completed_at = None
    for field, value in changes.items():
        setattr(task, field, value)
    if task.due_date is None:
        task.due_time = None
    db.commit()
    db.refresh(task)
    return task


def delete_task(db: Session, user_id: uuid.UUID, task_id: uuid.UUID) -> None:
    task = get_owned(db, Task, task_id, user_id, "Task")
    db.delete(task)
    db.commit()
