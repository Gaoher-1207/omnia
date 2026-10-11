import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.common.deps import CurrentUser, DbSession
from app.core.errors import NotFoundError
from app.core.time import local_today
from app.modules.ai import assistant, manual, service
from app.modules.ai.providers import PlanProvider
from app.modules.ai.schemas import (
    AIPlanOut,
    ChatReply,
    ChatRequest,
    DailyPlanRequest,
    ManualPlanItemIn,
    PlanOutcomeIn,
    ReplanProposalOut,
    ReplanRequest,
)

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
    return service.plan_out_for(db, plan)


@router.get("/daily-plan", response_model=AIPlanOut, summary="Latest plan for a date (default today)")
def get_daily_plan(user: CurrentUser, db: DbSession, plan_date: date | None = Query(default=None, alias="date")):
    plan = service.latest_plan(db, user.id, plan_date or local_today(user.profile.timezone))
    if plan is None:
        raise NotFoundError("Plan")
    return service.plan_out_for(db, plan)


@router.post(
    "/daily-plan/{plan_date}/items",
    response_model=AIPlanOut,
    responses={201: {"model": AIPlanOut, "description": "A plan was created for a day that had none"}},
    summary="Add a block to a day's plan by hand",
    description=(
        "Adds one block (from an owned task or subject, or a titled activity, break, rest or other block) to "
        "the latest plan for today or a later day, as a new revision. Nothing else moves. "
        "409 `plan_item_conflict` lists overlapping blocks and fixed commitments; 409 `plan_stale` when "
        "`base_revision` is no longer the latest; 422 `plan_item_invalid` for past, out-of-range or duplicate "
        "blocks. Planners treat manual blocks as fixed."
    ),
)
def add_plan_item(plan_date: date, body: ManualPlanItemIn, response: Response, user: CurrentUser, db: DbSession):
    plan, created = manual.add_item(db, user, plan_date, body)
    response.status_code = status.HTTP_201_CREATED if created else status.HTTP_200_OK
    return service.plan_out_for(db, plan)


@router.delete(
    "/daily-plan/{plan_date}/items/{item_key}",
    response_model=AIPlanOut,
    summary="Remove a block from a day's plan",
    description=(
        "Removes one block (added by hand or generated) from the latest plan for today or a later day, as a new "
        "revision; nothing else changes. Its task, subject, recorded outcome and credited study time are kept. "
        "Fixed commitments are not plan blocks. 409 `plan_item_stale` when the block is no longer in the latest "
        "plan; 409 `plan_stale` when `base_revision` is not the latest; 422 `plan_item_invalid` for a past day."
    ),
)
def remove_plan_item(
    plan_date: date,
    item_key: str,
    user: CurrentUser,
    db: DbSession,
    base_revision: int | None = Query(default=None, ge=1),
):
    return service.plan_out_for(db, manual.remove_item(db, user, plan_date, item_key, base_revision))


@router.post(
    "/replan/proposals",
    response_model=ReplanProposalOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a validated replan proposal without changing the plan",
)
def create_replan_proposal(body: ReplanRequest, user: CurrentUser, db: DbSession, provider: Provider):
    return service.create_replan_proposal(db, user, body, provider)


@router.get("/replan/proposals/{proposal_id}", response_model=ReplanProposalOut, summary="Get a replan proposal")
def get_replan_proposal(proposal_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.get_replan_proposal(db, user.id, proposal_id)


@router.post("/replan/proposals/{proposal_id}/apply", response_model=AIPlanOut, summary="Apply an approved replan")
def apply_replan_proposal(proposal_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.apply_replan_proposal(db, user, proposal_id)


@router.post(
    "/replan/proposals/{proposal_id}/dismiss",
    response_model=ReplanProposalOut,
    summary="Dismiss a replan proposal",
)
def dismiss_replan_proposal(proposal_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.dismiss_replan_proposal(db, user.id, proposal_id)


@router.put(
    "/daily-plan/{plan_date}/items/{item_key}/outcome",
    response_model=AIPlanOut,
    summary="Record what happened to a plan block",
    description=(
        "Marks one block of the latest plan for a day (today or earlier) as done, partly done or skipped. "
        "Never changes the schedule itself; replanning reads outcomes so finished work isn't planned again. "
        "A study block marked done is logged as a study session for its planned length; partly done earns only "
        "the `minutes` given; Focus time already inside the block is not counted twice. "
        "409 `plan_item_stale` when the block is no longer in the latest plan."
    ),
)
def record_plan_outcome(plan_date: date, item_key: str, body: PlanOutcomeIn, user: CurrentUser, db: DbSession):
    return service.record_outcome(db, user, plan_date, item_key, body.status, body.minutes)


@router.delete(
    "/daily-plan/{plan_date}/items/{item_key}/outcome",
    response_model=AIPlanOut,
    summary="Clear a plan block's recorded outcome",
)
def clear_plan_outcome(plan_date: date, item_key: str, user: CurrentUser, db: DbSession):
    return service.record_outcome(db, user, plan_date, item_key, None)
