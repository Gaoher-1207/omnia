from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.common.deps import CurrentUser, DbSession
from app.core.errors import NotFoundError
from app.core.time import local_today
from app.modules.ai import service
from app.modules.ai.providers import PlanProvider
from app.modules.ai.schemas import AIPlanOut, DailyPlanRequest

router = APIRouter(prefix="/ai", tags=["ai"])

Provider = Annotated[PlanProvider, Depends(service.get_provider)]


@router.post(
    "/daily-plan",
    response_model=AIPlanOut,
    responses={201: {"model": AIPlanOut, "description": "A new plan was generated"}},
    summary="Get or generate today's plan",
    description=(
        "Returns today's existing plan (200) unless `regenerate` is true, otherwise generates one (201). "
        "If the external AI provider fails, the rule-based planner answers instead and `is_fallback` is true."
    ),
)
def create_daily_plan(body: DailyPlanRequest, response: Response, user: CurrentUser, db: DbSession, provider: Provider):
    plan, created = service.generate_daily_plan(db, user, body, provider)
    response.status_code = status.HTTP_201_CREATED if created else status.HTTP_200_OK
    return service.plan_out(plan)


@router.get("/daily-plan", response_model=AIPlanOut, summary="Latest plan for a date (default today)")
def get_daily_plan(user: CurrentUser, db: DbSession, plan_date: date | None = Query(default=None, alias="date")):
    plan = service.latest_plan(db, user.id, plan_date or local_today(user.profile.timezone))
    if plan is None:
        raise NotFoundError("Plan")
    return service.plan_out(plan)
