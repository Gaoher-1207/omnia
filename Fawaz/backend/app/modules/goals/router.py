import uuid

from fastapi import APIRouter, Response, status

from app.common.deps import CurrentUser, DbSession
from app.common.ownership import get_owned
from app.modules.goals import service
from app.modules.goals.models import Goal
from app.modules.goals.schemas import GoalCreate, GoalOut, GoalUpdate

router = APIRouter(prefix="/goals", tags=["goals"])


@router.get("", response_model=list[GoalOut], summary="List my long-term goals")
def list_goals(user: CurrentUser, db: DbSession):
    return service.list_goals(db, user.id)


@router.post("", response_model=GoalOut, status_code=status.HTTP_201_CREATED, summary="Create a goal")
def create_goal(body: GoalCreate, user: CurrentUser, db: DbSession):
    return service.create_goal(db, user.id, body)


@router.get("/{goal_id}", response_model=GoalOut, summary="Get one goal")
def get_goal(goal_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return get_owned(db, Goal, goal_id, user.id, "Goal")


@router.patch(
    "/{goal_id}",
    response_model=GoalOut,
    summary="Update a goal (including completing or reopening it)",
    description="Omitted fields stay unchanged. Completing or reopening never changes the recorded values.",
)
def update_goal(goal_id: uuid.UUID, body: GoalUpdate, user: CurrentUser, db: DbSession):
    return service.update_goal(db, user.id, goal_id, body)


@router.delete("/{goal_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a goal")
def delete_goal(goal_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_goal(db, user.id, goal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
