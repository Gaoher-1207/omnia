import logging
import uuid
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.core.time import local_now
from app.modules.ai.constraints import (
    DEFAULT_TASK_MINUTES,
    hhmm,
    minutes,
    validate_candidate,
    window_start,
)
from app.modules.ai.context import build_context
from app.modules.ai.explanation import explain_plan
from app.modules.ai.models import AIPlan
from app.modules.ai.providers import (
    AnthropicProvider,
    PlanProvider,
    ProviderError,
    RulesProvider,
)
from app.modules.ai.schemas import AIPlanContent, AIPlanOut, DailyPlanRequest, PlanContext, PlanItemOut
from app.modules.users.models import User

logger = logging.getLogger("omnia.ai")


def get_provider() -> PlanProvider:
    settings = get_settings()
    configured_provider = settings.effective_planner_ai_provider
    if configured_provider == "ollama":
        from app.modules.ai.ollama import OllamaPlanProvider

        return OllamaPlanProvider(**settings.ollama_options())
    if configured_provider == "off":
        return RulesProvider()
    if configured_provider == "anthropic":
        return AnthropicProvider(
            api_key=settings.ai_api_key,
            model=settings.ai_model,
            base_url=settings.ai_base_url,
            timeout=settings.ai_timeout_seconds,
        )
    if configured_provider == "openrouter":
        from app.modules.ai.openrouter import OpenRouterPlanProvider

        return OpenRouterPlanProvider(**settings.openrouter_options())
    return RulesProvider()


def latest_plan(db: Session, user_id: uuid.UUID, plan_date: date) -> AIPlan | None:
    return db.scalar(
        select(AIPlan)
        .where(AIPlan.user_id == user_id, AIPlan.plan_date == plan_date)
        .order_by(AIPlan.created_at.desc())
        .limit(1)
    )


def plan_out(plan: AIPlan) -> AIPlanOut:
    content = plan.content
    return AIPlanOut(
        id=plan.id,
        plan_date=plan.plan_date,
        source=plan.source,
        is_fallback=plan.is_fallback,
        created_at=plan.created_at,
        summary=content["summary"],
        items=[PlanItemOut.model_validate(item) for item in content["items"]],
        tips=content["tips"],
        adjustments=content["adjustments"],
        planning_start_minutes=content.get("planning_start_minutes"),
        planning_end_minutes=content.get("planning_end_minutes"),
        validation_version=content.get("validation_version", 0),
        window_start=content.get("window_start"),
        window_end=content.get("window_end"),
        assumptions=content.get("assumptions", []),
        unscheduled=content.get("unscheduled", []),
        explanation=content.get("explanation"),
    )


def _to_stored(content: AIPlanContent, refs: dict[str, uuid.UUID], context: PlanContext) -> dict:
    """Persist only validated links. Unscheduled work is calculated, never model-authored."""
    items = []
    for item in content.items:
        task_id = refs[item.task_ref] if item.task_ref else None
        subject_id = refs[item.study_ref] if item.study_ref else None
        items.append(
            PlanItemOut(
                start=item.start,
                end=item.end,
                category=item.category,
                title=item.title,
                detail=item.detail,
                task_id=task_id,
                subject_id=subject_id,
            ).model_dump(mode="json")
        )
    unscheduled = []
    for task in context.open_tasks:
        if not any(i.task_ref == task.ref for i in content.items):
            unscheduled.append(
                {
                    "title": task.title,
                    "category": "task",
                    "task_id": str(refs[task.ref]),
                    "remaining_minutes": task.estimated_minutes or DEFAULT_TASK_MINUTES,
                    "reason": "deadline_passed"
                    if task.due_in_days is not None
                    and (
                        task.due_in_days < 0
                        or (
                            task.due_in_days == 0
                            and task.due_time is not None
                            and minutes(task.due_time) <= minutes(context.current_time)
                        )
                    )
                    else "not_scheduled",
                }
            )
    for block in context.study_blocks:
        allocated = sum(minutes(i.end) - minutes(i.start) for i in content.items if i.study_ref == block.ref)
        if allocated < block.minutes:
            unscheduled.append(
                {
                    "title": f"{block.subject}: {block.title}",
                    "category": "study",
                    "subject_id": str(refs[block.ref]),
                    "remaining_minutes": block.minutes - allocated,
                    "reason": "not_scheduled",
                }
            )
    assumptions = ["Manual commitments are excluded from free time; external calendar events are not included."]
    if any(t.estimated_minutes is None for t in context.open_tasks):
        assumptions.append("Tasks without an estimate use 30 minutes; tasks are scheduled as whole blocks.")
    if context.omitted_tasks:
        assumptions.append(
            f"Only the first {len(context.open_tasks)} open tasks were considered; "
            f"{context.omitted_tasks} additional tasks are outside this suggestion."
        )
    return {
        "planning_start_minutes": context.planning_start_minutes,
        "planning_end_minutes": context.planning_end_minutes,
        "validation_version": 1,
        "window_start": hhmm(window_start(context)),
        "window_end": hhmm(context.planning_end_minutes),
        "assumptions": assumptions,
        "unscheduled": unscheduled,
        "explanation": explain_plan(content, context, unscheduled).model_dump(),
        "summary": content.summary,
        "items": items,
        "tips": content.tips,
        "adjustments": content.adjustments,
    }


def generate_daily_plan(
    db: Session, user: User, request: DailyPlanRequest, provider: PlanProvider
) -> tuple[AIPlan, bool]:
    """Return (plan, created). Reuses today's plan unless regenerate is set."""
    now = local_now(user.profile.timezone)
    if not request.regenerate:
        existing = latest_plan(db, user.id, now.date())
        if existing is not None:
            return existing, False

    limiter.hit(f"ai:{user.id}", get_settings().ai_rate_limit_per_hour, 3600)
    context, refs = build_context(db, user, now, request.note)

    source, fallback_reason = provider.name, None
    validation_success = False
    try:
        try:
            content = validate_candidate(provider.generate(context), context)
            validation_success = True
        except ValueError as exc:
            raise ProviderError("invalid_plan") from exc
    except ProviderError as exc:
        if provider.name == RulesProvider.name:
            raise
        logger.warning("AI provider %s failed (%s); using rules fallback", provider.name, exc.reason)
        content = validate_candidate(RulesProvider().generate(context), context)
        source, fallback_reason = RulesProvider.name, exc.reason

    metadata = getattr(provider, "last_metadata", None)
    if metadata is not None:
        metadata["validation_success"] = validation_success
        metadata["success"] = metadata.get("success", False) and validation_success
        logger.info(
            "AI request provider=%s primary_model=%s actual_model=%s fallback_used=%s "
            "latency_ms=%s success=%s validation_success=%s",
            metadata.get("configured_provider"),
            metadata.get("configured_primary_model"),
            metadata.get("actual_model"),
            metadata.get("fallback_used"),
            metadata.get("latency_ms"),
            metadata.get("success"),
            metadata.get("validation_success"),
        )

    plan = AIPlan(
        user_id=user.id,
        plan_date=now.date(),
        source=source,
        is_fallback=fallback_reason is not None,
        fallback_reason=fallback_reason,
        content=_to_stored(content, refs, context),
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan, True
