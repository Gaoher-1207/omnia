from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.common.deps import CurrentUser, DbSession
from app.core.errors import NotFoundError
from app.core.time import local_today
from app.modules.ai import assistant, service
from app.modules.ai.providers import PlanProvider
from app.modules.ai.schemas import AIPlanOut, ChatReply, ChatRequest, DailyPlanRequest

router = APIRouter(prefix="/ai", tags=["ai"])

Provider = Annotated[PlanProvider, Depends(service.get_provider)]
ChatProviderDep = Annotated[assistant.ChatProvider | None, Depends(assistant.get_chat_provider)]


@router.post(
    "/chat",
    response_model=ChatReply,
    summary="Ask Omnia about your day (read-only)",
    description=(
        "Answers from the signed-in user's own OMNIA data, which the server gathers itself. "
        "Changes nothing. 503 when the assistant is switched off, offline or its model is missing; "
        "502 when the model times out or gives an unusable answer."
    ),
)
def chat(body: ChatRequest, user: CurrentUser, db: DbSession, provider: ChatProviderDep):
    return assistant.answer(db, user, body, provider)


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
