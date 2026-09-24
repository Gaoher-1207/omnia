import logging
import uuid
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.core.time import local_now
from app.modules.ai.context import build_context
from app.modules.ai.models import AIPlan
from app.modules.ai.providers import (
    AnthropicProvider,
    PlanProvider,
    ProviderError,
    RulesProvider,
)
from app.modules.ai.schemas import AIPlanContent, AIPlanOut, DailyPlanRequest, PlanItemOut
from app.modules.study.service import list_subjects
from app.modules.users.models import User

logger = logging.getLogger("omnia.ai")


def get_provider() -> PlanProvider:
    settings = get_settings()
    if settings.ai_provider == "anthropic":
        return AnthropicProvider(
            api_key=settings.ai_api_key,
            model=settings.ai_model,
            base_url=settings.ai_base_url,
            timeout=settings.ai_timeout_seconds,
        )
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
    )


def _subject_for(title: str, subjects: dict[str, uuid.UUID]) -> uuid.UUID | None:
    """Match a study item to a subject by name (longest name first, case-insensitive)."""
    lowered = title.lower()
    for name in sorted(subjects, key=len, reverse=True):
        if name.lower() in lowered:
            return subjects[name]
    return None


def _to_stored(content: AIPlanContent, refs: dict[str, uuid.UUID], subjects: dict[str, uuid.UUID]) -> dict:
    """Swap task refs back to real task ids; drop refs the provider made up; link study items to subjects."""
    items = []
    for item in content.items:
        task_id = refs.get(item.task_ref) if item.task_ref else None
        subject_id = _subject_for(item.title, subjects) if item.category == "study" else None
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
    return {
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
    try:
        content = provider.generate(context)
    except ProviderError as exc:
        if provider.name == RulesProvider.name:
            raise
        logger.warning("AI provider %s failed (%s); using rules fallback", provider.name, exc.reason)
        content = RulesProvider().generate(context)
        source, fallback_reason = RulesProvider.name, exc.reason

    plan = AIPlan(
        user_id=user.id,
        plan_date=now.date(),
        source=source,
        is_fallback=fallback_reason is not None,
        fallback_reason=fallback_reason,
        content=_to_stored(content, refs, {s.name: s.id for s in list_subjects(db, user.id)}),
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan, True
