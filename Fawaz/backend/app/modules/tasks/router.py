import uuid
from datetime import date

from fastapi import APIRouter, Query, Response, status

from app.common.deps import CurrentUser, DbSession
from app.common.ownership import get_owned
from app.common.schemas import Page
from app.modules.tasks import service
from app.modules.tasks.models import Task
from app.modules.tasks.schemas import Priority, TaskCreate, TaskOut, TaskStatus, TaskUpdate

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=Page[TaskOut], summary="List my tasks")
def list_tasks(
    user: CurrentUser,
    db: DbSession,
    status_filter: TaskStatus | None = Query(default=None, alias="status"),
    priority: Priority | None = None,
    due_on_or_before: date | None = None,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
):
    items, total = service.list_tasks(
        db,
        user.id,
        status=status_filter,
        priority=priority,
        due_on_or_before=due_on_or_before,
        limit=limit,
        offset=offset,
    )
    return Page[TaskOut](items=items, total=total, limit=limit, offset=offset)


@router.post("", response_model=TaskOut, status_code=status.HTTP_201_CREATED, summary="Create a task")
def create_task(body: TaskCreate, user: CurrentUser, db: DbSession):
    return service.create_task(db, user.id, body)


@router.get("/{task_id}", response_model=TaskOut, summary="Get one task")
def get_task(task_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return get_owned(db, Task, task_id, user.id, "Task")


@router.patch("/{task_id}", response_model=TaskOut, summary="Update a task (including completing it)")
def update_task(task_id: uuid.UUID, body: TaskUpdate, user: CurrentUser, db: DbSession):
    return service.update_task(db, user.id, task_id, body)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a task")
def delete_task(task_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_task(db, user.id, task_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
