import hashlib
import json
import logging
import re
import uuid
from collections import Counter
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.planning_lock import lock_planning_state
from app.core.config import get_settings
from app.core.errors import AppError, NotFoundError
from app.core.rate_limit import limiter
from app.core.time import local_now, utcnow
from app.modules.ai.constraints import (
    DEFAULT_TASK_MINUTES,
    hhmm,
    minutes,
    task_deadline,
    validate_candidate,
    window_start,
)
from app.modules.ai.context import build_context
from app.modules.ai.explanation import explain_plan
from app.modules.ai.models import AIPlan, ReplanProposal
from app.modules.ai.providers import (
    AnthropicProvider,
    PlanProvider,
    ProviderError,
    RulesProvider,
)
from app.modules.ai.schemas import (
    AIPlanContent,
    AIPlanOut,
    DailyPlanRequest,
    PlanContext,
    PlanItem,
    PlanItemOut,
    ReplanDraft,
    ReplanOperation,
    ReplanProposalOut,
    ReplanRequest,
)
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
        .order_by(AIPlan.revision.desc(), AIPlan.created_at.desc())
        .limit(1)
    )


def plan_out(plan: AIPlan) -> AIPlanOut:
    content = plan.content
    return AIPlanOut(
        id=plan.id,
        revision=plan.revision,
        plan_date=plan.plan_date,
        source=plan.source,
        is_fallback=plan.is_fallback,
        created_at=plan.created_at,
        summary=content["summary"],
        items=[
            PlanItemOut.model_validate({"item_key": item.get("item_key") or f"{plan.id.hex}:{index}", **item})
            for index, item in enumerate(content["items"])
        ],
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
                item_key=uuid.uuid4().hex,
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
    lock_planning_state(db, user.id)
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

    previous = latest_plan(db, user.id, now.date())
    plan = AIPlan(
        user_id=user.id,
        plan_date=now.date(),
        revision=previous.revision + 1 if previous is not None else 1,
        source=source,
        is_fallback=fallback_reason is not None,
        fallback_reason=fallback_reason,
        content=_to_stored(content, refs, context),
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan, True


class ReplanUnavailableError(AppError):
    status_code = 503
    code = "service_unavailable"

    def __init__(self, message: str):
        super().__init__(message)


class ReplanInvalidError(AppError):
    status_code = 422
    code = "replan_invalid"

    def __init__(self, message: str):
        super().__init__(message)


class ReplanConflictError(AppError):
    status_code = 409
    code = "replan_proposal_conflict"

    def __init__(self, message: str, code: str = "replan_proposal_conflict"):
        super().__init__(message)
        self.code = code


def _planning_fingerprint(plan: AIPlan, context: PlanContext, refs: dict[str, uuid.UUID]) -> str:
    state = context.model_dump(mode="json")
    # Wall-clock movement alone does not invalidate a proposal; application revalidates
    # against the new current time before committing.
    state.pop("current_time", None)
    state.pop("free_intervals", None)
    state.pop("note", None)
    payload = {
        "plan_id": str(plan.id),
        "revision": plan.revision,
        "content": plan.content,
        "context": state,
        "refs": {key: str(value) for key, value in sorted(refs.items())},
        "commitments": [item.model_dump(mode="json") for item in context.commitments],
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
    return hashlib.sha256(encoded).hexdigest()


def _item_key(plan: AIPlan, item: dict, index: int) -> str:
    return str(item.get("item_key") or f"{plan.id.hex}:{index}")


def _provider_schedule_item(item: dict, refs: dict[str, uuid.UUID]) -> dict:
    value = {key: item.get(key) for key in ("start", "end", "category", "title", "detail")}
    task_id = item.get("task_id")
    subject_id = item.get("subject_id")
    if task_id:
        task_uuid = uuid.UUID(str(task_id))
        ref = next((key for key, value in refs.items() if value == task_uuid and key.startswith("t")), None)
        value["task_ref"] = ref
    if subject_id:
        subject_uuid = uuid.UUID(str(subject_id))
        ref = next((key for key, value in refs.items() if value == subject_uuid and key.startswith("b")), None)
        value["study_ref"] = ref
    return value


def _stored_schedule(draft: ReplanDraft, refs: dict[str, uuid.UUID], context: PlanContext) -> list[dict]:
    content = AIPlanContent(summary=draft.summary, items=draft.items, tips=[], adjustments=[])
    checked = validate_candidate(content, context)
    _validate_fixed_commitments(checked.items, context)
    result = []
    for item in checked.items:
        result.append(
            {
                "item_key": uuid.uuid4().hex,
                "start": item.start,
                "end": item.end,
                "category": item.category,
                "title": item.title,
                "detail": item.detail,
                "task_ref": item.task_ref,
                "study_ref": item.study_ref,
                "task_id": str(refs[item.task_ref]) if item.task_ref else None,
                "subject_id": str(refs[item.study_ref]) if item.study_ref else None,
            }
        )
    return result


def _validate_fixed_commitments(items: list[PlanItem], context: PlanContext) -> None:
    for item in items:
        start, end = minutes(item.start), minutes(item.end)
        if any(start < commitment.end_minutes and end > commitment.start_minutes for commitment in context.commitments):
            raise ValueError("overlaps_fixed_commitment")
        if context.free_intervals is not None and not any(
            start >= interval.start_minutes and end <= interval.end_minutes for interval in context.free_intervals
        ):
            raise ValueError("outside_free_interval")


def _validate_required_work(
    after: list[dict], context: PlanContext, refs: dict[str, uuid.UUID], before: list[dict]
) -> None:
    start = window_start(context)
    due_today_refs = {
        task.ref
        for task in context.open_tasks
        if task.due_in_days == 0
        and task_deadline(task, context.planning_end_minutes) - start
        >= (task.estimated_minutes or DEFAULT_TASK_MINUTES)
    }
    required_ids = {str(task_id) for ref, task_id in refs.items() if ref in due_today_refs}
    if required_ids:
        scheduled_ids = {str(item.get("task_id")) for item in after if item.get("task_id")}
        if not required_ids.issubset(scheduled_ids):
            raise ValueError("required_due_today_task_removed")

    required_study = Counter()
    for item in before:
        if item.get("category") == "study" and minutes(item["start"]) >= start:
            key = str(item.get("subject_id") or item.get("title"))
            required_study[key] += minutes(item["end"]) - minutes(item["start"])
    scheduled_study = Counter()
    for item in after:
        if item.get("category") == "study":
            key = str(item.get("subject_id") or item.get("title"))
            scheduled_study[key] += minutes(item["end"]) - minutes(item["start"])
    if any(scheduled_study[key] < needed for key, needed in required_study.items()):
        raise ValueError("required_study_work_reduced")


def _identity(item: dict) -> tuple:
    return (
        item.get("category"),
        item.get("task_id"),
        item.get("subject_id"),
        item.get("title") if not item.get("task_id") and not item.get("subject_id") else None,
    )


def _operations(before: list[dict], after: list[dict], explanation: str) -> list[dict]:
    unused = set(range(len(after)))
    operations = []
    for index, old in enumerate(before):
        candidate = next((i for i in sorted(unused) if _identity(old) == _identity(after[i])), None)
        old_public = {k: old.get(k) for k in ("start", "end", "category", "title", "task_id", "subject_id")}
        if candidate is None:
            operations.append(
                ReplanOperation(
                    kind="REMOVE",
                    item_key=str(old.get("item_key", f"legacy:{index}")),
                    entity_id=uuid.UUID(str(old["task_id"]))
                    if old.get("task_id")
                    else (uuid.UUID(str(old["subject_id"])) if old.get("subject_id") else None),
                    before=old_public,
                    reason=explanation[:280],
                ).model_dump(mode="json")
            )
            continue
        unused.remove(candidate)
        new = after[candidate]
        new["item_key"] = str(old.get("item_key", f"legacy:{index}"))
        new_public = {k: new.get(k) for k in ("start", "end", "category", "title", "task_id", "subject_id")}
        if old_public == new_public:
            continue
        old_duration = minutes(old["end"]) - minutes(old["start"])
        new_duration = minutes(new["end"]) - minutes(new["start"])
        kind = "SHORTEN" if new_duration < old_duration else ("MOVE" if new_duration == old_duration else "RESCHEDULE")
        entity = old.get("task_id") or old.get("subject_id")
        operations.append(
            ReplanOperation(
                kind=kind,
                item_key=str(old.get("item_key", f"legacy:{index}")),
                entity_id=uuid.UUID(str(entity)) if entity else None,
                before=old_public,
                after=new_public,
                reason=explanation[:280],
            ).model_dump(mode="json")
        )
    for index in sorted(unused):
        item = after[index]
        entity = item.get("task_id") or item.get("subject_id")
        operations.append(
            ReplanOperation(
                kind="ADD",
                item_key=item["item_key"],
                entity_id=uuid.UUID(str(entity)) if entity else None,
                after={k: item.get(k) for k in ("start", "end", "category", "title", "task_id", "subject_id")},
                reason=explanation[:280],
            ).model_dump(mode="json")
        )
    return operations


_OPERATION_FIELDS = ("start", "end", "category", "title", "task_id", "subject_id")


def _operation_item(item: dict) -> dict:
    return {key: item.get(key) for key in _OPERATION_FIELDS}


def _validate_operations(
    before: list[dict], after: list[dict], operations: list[dict], refs: dict[str, uuid.UUID]
) -> None:
    """Check each server-derived operation against both schedules and replay the diff."""
    before_by_key = {str(item["item_key"]): item for item in before}
    after_by_key = {str(item["item_key"]): item for item in after}
    if len(before_by_key) != len(before) or len(after_by_key) != len(after):
        raise ValueError("duplicate_item_key")

    operation_by_key: dict[str, ReplanOperation] = {}
    replay = {key: _operation_item(item) for key, item in before_by_key.items()}
    for raw in operations:
        operation = ReplanOperation.model_validate(raw)
        key = operation.item_key
        if key in operation_by_key:
            raise ValueError("duplicate_operation")
        operation_by_key[key] = operation
        old = before_by_key.get(key)
        new = after_by_key.get(key)
        entity = (old or new or {}).get("task_id") or (old or new or {}).get("subject_id")
        if (str(operation.entity_id) if operation.entity_id else None) != (str(entity) if entity else None):
            raise ValueError("operation_entity_mismatch")

        if operation.kind == "REMOVE":
            if old is None or new is not None or operation.after is not None:
                raise ValueError("invalid_remove_operation")
            if operation.before != _operation_item(old):
                raise ValueError("operation_before_mismatch")
            replay.pop(key)
            continue

        if operation.kind == "ADD":
            if old is not None or new is None or operation.before is not None:
                raise ValueError("invalid_add_operation")
            if operation.after != _operation_item(new):
                raise ValueError("operation_after_mismatch")
            if new.get("category") in {"task", "study"}:
                entity_ref = new.get("task_ref") if new["category"] == "task" else new.get("study_ref")
                if entity_ref not in refs:
                    raise ValueError("unowned_operation_entity")
            replay[key] = _operation_item(new)
            continue

        if operation.kind == "UNCHANGED" or old is None or new is None:
            raise ValueError("invalid_change_operation")
        if _identity(old) != _identity(new):
            raise ValueError("operation_changes_entity")
        if operation.before != _operation_item(old) or operation.after != _operation_item(new):
            raise ValueError("operation_schedule_mismatch")
        old_duration = minutes(old["end"]) - minutes(old["start"])
        new_duration = minutes(new["end"]) - minutes(new["start"])
        expected_kind = (
            "SHORTEN" if new_duration < old_duration else ("MOVE" if new_duration == old_duration else "RESCHEDULE")
        )
        if operation.kind != expected_kind:
            raise ValueError("operation_kind_mismatch")
        replay[key] = _operation_item(new)

    # Every change in the full schedule must have exactly one matching operation.
    for key in set(before_by_key) | set(after_by_key):
        old, new = before_by_key.get(key), after_by_key.get(key)
        changed = old is None or new is None or _operation_item(old) != _operation_item(new)
        if changed != (key in operation_by_key):
            raise ValueError("operation_set_incomplete")
    target = {key: _operation_item(item) for key, item in after_by_key.items()}
    if replay != target:
        raise ValueError("operation_replay_mismatch")


def _normalized_words(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", value.casefold()))


def _validate_request_semantics(
    request: str, before: list[dict], after: list[dict], context: PlanContext, refs: dict[str, uuid.UUID]
) -> dict:
    """Enforce only clear, mechanically verifiable instructions; report opaque intent as unverified."""
    text = _normalized_words(request)
    checks: list[dict[str, str]] = []
    named: list[dict] = []
    for item in before:
        title = _normalized_words(item.get("title") or "")
        if len(title) >= 3 and title in text:
            named.append(item)
    unique_named = {str(item.get("item_key")): item for item in named}

    time_match = re.search(r"\b(?:to|at)\s+([01]?\d|2[0-3]):([0-5]\d)\b", request, re.IGNORECASE)
    if (
        time_match
        and re.search(r"\b(move|reschedule|shift|start)\b", request, re.IGNORECASE)
        and len(unique_named) == 1
    ):
        old = next(iter(unique_named.values()))
        expected_start = f"{int(time_match.group(1)):02d}:{time_match.group(2)}"
        new = next((item for item in after if _identity(item) == _identity(old)), None)
        if new is None or new.get("start") != expected_start:
            raise ValueError("request_intent_not_satisfied")
        checks.append({"kind": "explicit_start_time", "result": "satisfied"})

    direction = None
    if re.search(r"\b(move|reschedule|shift)\b.*\blater\b", request, re.IGNORECASE):
        direction = "later"
    elif re.search(r"\b(move|reschedule|shift)\b.*\b(earlier|sooner)\b", request, re.IGNORECASE):
        direction = "earlier"
    if direction and len(unique_named) == 1:
        old = next(iter(unique_named.values()))
        new = next((item for item in after if _identity(item) == _identity(old)), None)
        if (
            new is None
            or (direction == "later" and minutes(new["start"]) <= minutes(old["start"]))
            or (direction == "earlier" and minutes(new["start"]) >= minutes(old["start"]))
        ):
            raise ValueError("request_intent_not_satisfied")
        checks.append({"kind": f"move_{direction}", "result": "satisfied"})

    if re.search(r"\b(remove|delete|cancel|drop)\b", request, re.IGNORECASE) and len(unique_named) == 1:
        old = next(iter(unique_named.values()))
        if any(_identity(item) == _identity(old) for item in after):
            raise ValueError("request_intent_not_satisfied")
        checks.append({"kind": "remove_named_item", "result": "satisfied"})

    if re.search(r"\b(shorten|reduce)\b", request, re.IGNORECASE) and len(unique_named) == 1:
        old = next(iter(unique_named.values()))
        old_minutes = minutes(old["end"]) - minutes(old["start"])
        new_minutes = sum(
            minutes(item["end"]) - minutes(item["start"]) for item in after if _identity(item) == _identity(old)
        )
        if new_minutes >= old_minutes:
            raise ValueError("request_intent_not_satisfied")
        checks.append({"kind": "shorten_named_item", "result": "satisfied"})

    study_increase = re.search(r"\b(more|increase)\b.*\b(study|revision)\b", request, re.IGNORECASE)
    if study_increase:
        named_subjects = {
            str(refs[block.ref])
            for block in context.study_blocks
            if block.ref in refs and _normalized_words(block.subject) in text
        }
        if len(named_subjects) == 1:
            subject_id = next(iter(named_subjects))
            old_minutes = sum(
                minutes(item["end"]) - minutes(item["start"])
                for item in before
                if item.get("category") == "study" and str(item.get("subject_id")) == subject_id
            )
            new_minutes = sum(
                minutes(item["end"]) - minutes(item["start"])
                for item in after
                if item.get("category") == "study" and str(item.get("subject_id")) == subject_id
            )
            if new_minutes <= old_minutes:
                raise ValueError("request_intent_not_satisfied")
            checks.append({"kind": "increase_subject_study", "result": "satisfied"})

    return {
        "deterministically_checked": bool(checks),
        "checks": checks,
        "other_intent": "not_deterministically_verifiable" if not checks else None,
    }


def _proposal_out(proposal: ReplanProposal) -> ReplanProposalOut:
    return ReplanProposalOut(
        id=proposal.id,
        base_plan_id=proposal.base_plan_id,
        base_revision=proposal.base_revision,
        plan_date=proposal.plan_date,
        status=proposal.status,
        request=proposal.request,
        summary=proposal.summary,
        explanation=proposal.explanation,
        operations=[ReplanOperation.model_validate(item) for item in proposal.operations],
        schedule=[PlanItemOut.model_validate(item) for item in proposal.schedule],
        warnings=proposal.warnings,
        validation=proposal.validation,
        created_at=proposal.created_at,
        expires_at=proposal.expires_at,
        applied_at=proposal.applied_at,
        dismissed_at=proposal.dismissed_at,
    )


def create_replan_proposal(
    db: Session, user: User, request: ReplanRequest, provider: PlanProvider
) -> ReplanProposalOut:
    lock_planning_state(db, user.id)
    now = local_now(user.profile.timezone)
    plan_date = request.plan_date or now.date()
    if plan_date != now.date():
        raise ReplanInvalidError("Replanning currently supports today's plan only.")
    plan = latest_plan(db, user.id, plan_date)
    if plan is None:
        raise ReplanInvalidError("Generate today's plan before requesting a replan.")
    limiter.hit(f"ai:{user.id}", get_settings().ai_rate_limit_per_hour, 3600)
    context, refs = build_context(db, user, now, None)
    method = getattr(provider, "generate_replan", None)
    baseline = [
        {**item, "item_key": _item_key(plan, item, index), **_provider_schedule_item(item, refs)}
        for index, item in enumerate(plan.content.get("items", []))
    ]
    current = [
        {
            key: item.get(key)
            for key in ("item_key", "start", "end", "category", "title", "detail", "task_ref", "study_ref")
        }
        for item in baseline
    ]
    payload = {
        "request": request.request,
        "plan_date": plan_date.isoformat(),
        "current_plan_revision": plan.revision,
        "current_schedule": current,
        "context": context.model_dump(mode="json"),
        "hard_constraints": {
            "earliest_start": hhmm(window_start(context)),
            "latest_end": hhmm(context.planning_end_minutes),
            "free_intervals": [item.model_dump(mode="json") for item in (context.free_intervals or [])],
        },
    }
    base_fingerprint = _planning_fingerprint(plan, context, refs)
    db.commit()  # Release the owner lock while waiting for the model.
    effective_provider = provider
    fallback_used = False
    try:
        if method is None:
            raise ProviderError("provider_does_not_support_replanning")
        draft = method(payload)
    except ProviderError as exc:
        logger.warning("Replan provider failed (%s); using deterministic rules fallback", exc.reason)
        effective_provider = RulesProvider()
        fallback_used = True
        try:
            draft = effective_provider.generate_replan(payload)
        except (ProviderError, ValueError, TypeError, KeyError):
            raise ReplanUnavailableError(
                "Neither the configured AI provider nor the deterministic replanner could prepare a safe proposal."
            ) from None
    try:
        schedule = _stored_schedule(draft, refs, context)
        _validate_required_work(schedule, context, refs, baseline)
        semantic_validation = _validate_request_semantics(request.request, baseline, schedule, context, refs)
        operations = _operations(baseline, schedule, draft.explanation)
        _validate_operations(baseline, schedule, operations, refs)
    except (ValueError, TypeError) as exc:
        logger.info("Replan proposal rejected by validation (%s)", type(exc).__name__)
        if fallback_used:
            raise ReplanUnavailableError(
                "The deterministic fallback could not prepare a proposal that satisfies the request "
                "and plan constraints."
            ) from None
        raise ReplanInvalidError("OmniAI returned a schedule that did not pass validation.") from None
    lock_planning_state(db, user.id)
    fresh_plan = latest_plan(db, user.id, plan_date)
    fresh_now = local_now(user.profile.timezone)
    fresh_context, fresh_refs = build_context(db, user, fresh_now, None)
    if (
        fresh_plan is None
        or fresh_plan.id != plan.id
        or _planning_fingerprint(fresh_plan, fresh_context, fresh_refs) != base_fingerprint
    ):
        db.rollback()
        raise ReplanConflictError(
            "The plan or planning state changed while OmniAI prepared the proposal.", "replan_proposal_stale"
        )
    proposal = ReplanProposal(
        user_id=user.id,
        base_plan_id=plan.id,
        base_revision=plan.revision,
        base_fingerprint=base_fingerprint,
        plan_date=plan_date,
        status="pending",
        provider=effective_provider.name,
        request=request.request,
        summary=draft.summary,
        explanation=draft.explanation,
        operations=operations,
        schedule=schedule,
        warnings=[
            "Existing plan blocks have no completion flag; past blocks are historical and are not marked complete.",
            *(
                ["The configured AI provider was unavailable; this proposal uses the deterministic rules planner."]
                if fallback_used
                else []
            ),
            *(
                ["Some parts of the request could not be checked deterministically; review the full schedule."]
                if semantic_validation["other_intent"]
                else []
            ),
        ],
        validation={
            "valid": True,
            "validator": "validate_candidate",
            "applicable": True,
            "fallback_used": fallback_used,
            "semantic": semantic_validation,
            "operations_validated": True,
        },
        expires_at=utcnow() + timedelta(minutes=30),
    )
    db.add(proposal)
    db.commit()
    db.refresh(proposal)
    return _proposal_out(proposal)


def get_replan_proposal(db: Session, user_id: uuid.UUID, proposal_id: uuid.UUID) -> ReplanProposalOut:
    lock_planning_state(db, user_id)
    proposal = db.scalar(
        select(ReplanProposal)
        .where(ReplanProposal.id == proposal_id, ReplanProposal.user_id == user_id)
        .with_for_update()
    )
    if proposal is None:
        raise NotFoundError("Replan proposal")
    if proposal.status == "pending" and proposal.expires_at <= utcnow():
        proposal.status = "expired"
        db.commit()
        db.refresh(proposal)
    return _proposal_out(proposal)


def _proposal_to_draft(proposal: ReplanProposal, refs: dict[str, uuid.UUID]) -> ReplanDraft:
    reverse_tasks = {value: key for key, value in refs.items() if key.startswith("t")}
    reverse_study = {value: key for key, value in refs.items() if key.startswith("b")}
    items = []
    for saved in proposal.schedule:
        task_ref = saved.get("task_ref") or (
            reverse_tasks.get(uuid.UUID(saved["task_id"])) if saved.get("task_id") else None
        )
        study_ref = saved.get("study_ref") or (
            reverse_study.get(uuid.UUID(saved["subject_id"])) if saved.get("subject_id") else None
        )
        items.append(
            PlanItem(
                start=saved["start"],
                end=saved["end"],
                category=saved["category"],
                title=saved["title"],
                detail=saved.get("detail"),
                task_ref=task_ref,
                study_ref=study_ref,
            )
        )
    return ReplanDraft(summary=proposal.summary, explanation=proposal.explanation, items=items)


def apply_replan_proposal(db: Session, user: User, proposal_id: uuid.UUID) -> AIPlanOut:
    lock_planning_state(db, user.id)
    proposal = db.scalar(
        select(ReplanProposal)
        .where(ReplanProposal.id == proposal_id, ReplanProposal.user_id == user.id)
        .with_for_update()
    )
    if proposal is None:
        raise NotFoundError("Replan proposal")
    now_utc = utcnow()
    if proposal.status != "pending":
        raise ReplanConflictError("This replan proposal is no longer pending.")
    if proposal.expires_at <= now_utc:
        proposal.status = "expired"
        db.commit()
        raise ReplanConflictError("This replan proposal has expired.", "replan_proposal_expired")
    now = local_now(user.profile.timezone)
    current = latest_plan(db, user.id, proposal.plan_date)
    if current is None or current.id != proposal.base_plan_id or current.revision != proposal.base_revision:
        proposal.status = "stale"
        db.commit()
        raise ReplanConflictError("The plan or planning state changed after this proposal.", "replan_proposal_stale")
    context, refs = build_context(db, user, now, None)
    if _planning_fingerprint(current, context, refs) != proposal.base_fingerprint:
        proposal.status = "stale"
        db.commit()
        raise ReplanConflictError("The plan or planning state changed after this proposal.", "replan_proposal_stale")
    if any(minutes(item["start"]) < window_start(context) for item in proposal.schedule):
        proposal.status = "stale"
        db.commit()
        raise ReplanConflictError("The proposed schedule is now in the past.", "replan_proposal_stale")
    try:
        baseline = [
            {**item, "item_key": _item_key(current, item, index), **_provider_schedule_item(item, refs)}
            for index, item in enumerate(current.content.get("items", []))
        ]
        _validate_operations(baseline, proposal.schedule, proposal.operations, refs)
        draft = _proposal_to_draft(proposal, refs)
        content = AIPlanContent(summary=draft.summary, items=draft.items, tips=[], adjustments=[])
        validated = validate_candidate(content, context)
        _validate_fixed_commitments(validated.items, context)
        stored = _to_stored(validated, refs, context)
        _validate_required_work(stored["items"], context, refs, baseline)
        _validate_request_semantics(proposal.request, baseline, proposal.schedule, context, refs)
        by_identity = {}
        for item in proposal.schedule:
            by_identity.setdefault(_identity(item), []).append(item)
        for item in stored["items"]:
            identity = _identity(item)
            previous = by_identity.get(identity, [])
            if previous:
                item["item_key"] = previous.pop(0)["item_key"]
        stored["summary"] = proposal.summary
        stored["adjustments"] = [proposal.explanation[:280]]
    except (ValueError, TypeError, KeyError) as exc:
        proposal.status = "invalid"
        db.commit()
        logger.info("Stored replan failed revalidation (%s)", type(exc).__name__)
        raise ReplanInvalidError("This replan proposal no longer passes validation.") from None
    try:
        result = AIPlan(
            user_id=user.id,
            plan_date=proposal.plan_date,
            revision=current.revision + 1,
            source=proposal.provider,
            is_fallback=False,
            fallback_reason=None,
            content=stored,
        )
        db.add(result)
        proposal.status = "applied"
        proposal.applied_at = now_utc
        db.commit()
        db.refresh(result)
    except Exception:
        db.rollback()
        raise
    return plan_out(result)


def dismiss_replan_proposal(db: Session, user_id: uuid.UUID, proposal_id: uuid.UUID) -> ReplanProposalOut:
    lock_planning_state(db, user_id)
    proposal = db.scalar(
        select(ReplanProposal)
        .where(ReplanProposal.id == proposal_id, ReplanProposal.user_id == user_id)
        .with_for_update()
    )
    if proposal is None:
        raise NotFoundError("Replan proposal")
    if proposal.status != "pending":
        raise ReplanConflictError("This replan proposal is no longer pending.")
    if proposal.expires_at <= utcnow():
        proposal.status = "expired"
    else:
        proposal.status = "dismissed"
        proposal.dismissed_at = utcnow()
    db.commit()
    db.refresh(proposal)
    return _proposal_out(proposal)
