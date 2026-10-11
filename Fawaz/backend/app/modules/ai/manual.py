"""Blocks the user adds to, or removes from, a day's plan by hand.

A manual block is stored in the plan like any other block (same item_key,
outcome and study-credit behaviour) with `"manual": true`. Planners treat it
as fixed: build_context subtracts it from free time and lists it with the
fixed commitments, generation and replanning copy it into every new revision
unchanged, and no model ever sees it as editable. Adding one never moves or
overwrites anything; an overlap is refused with the blocks it overlaps.

Removing a block (manual or generated) writes a new revision without it and
changes nothing else: its task, subject, recorded outcome and any study time
already credited stay as they are. Fixed commitments are not plan blocks and
can't be removed here.
"""

import copy
import uuid
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.planning_lock import lock_planning_state
from app.core import metrics
from app.core.errors import AppError, NotFoundError
from app.core.time import local_now
from app.modules.ai.constraints import hhmm, minutes
from app.modules.ai.models import AIPlan
from app.modules.ai.schemas import ManualPlanItemIn, PlanItemOut
from app.modules.commitments.service import for_day, list_owned
from app.modules.study.models import Subject
from app.modules.tasks.models import Task
from app.modules.users.models import User

MAX_DAYS_AHEAD = 60
MAX_ITEMS = 40
DAY_MINUTES = 24 * 60


class ManualItemInvalidError(AppError):
    status_code = 422
    code = "plan_item_invalid"

    def __init__(self, message: str):
        super().__init__(message)


class ManualItemConflictError(AppError):
    status_code = 409

    def __init__(self, message: str, code: str, details: list | None = None):
        super().__init__(message, details=details)
        self.code = code


def is_manual(item: dict) -> bool:
    return bool(item.get("manual"))


def manual_items(plan: AIPlan | None) -> list[dict]:
    if plan is None:
        return []
    return [item for item in plan.content.get("items", []) if is_manual(item)]


def _latest(db: Session, user_id: uuid.UUID, plan_date: date) -> AIPlan | None:
    return db.scalar(
        select(AIPlan)
        .where(AIPlan.user_id == user_id, AIPlan.plan_date == plan_date)
        .order_by(AIPlan.revision.desc(), AIPlan.created_at.desc())
        .limit(1)
    )


def latest_manual_items(db: Session, user_id: uuid.UUID, plan_date: date) -> list[dict]:
    return manual_items(_latest(db, user_id, plan_date))


def with_manual(items: list[dict], manual: list[dict]) -> list[dict]:
    """A planner's new items plus the user's manual blocks, in time order."""
    return sorted([*items, *(copy.deepcopy(item) for item in manual)], key=lambda item: item["start"])


def _keyed_items(plan: AIPlan) -> list[dict]:
    """Copies of the plan's items, each carrying the key it is known by, so a
    new revision keeps every block's identity (and its recorded outcome)."""
    return [
        {**copy.deepcopy(item), "item_key": str(item.get("item_key") or f"{plan.id.hex}:{index}")}
        for index, item in enumerate(plan.content.get("items", []))
    ]


def _revision(plan: AIPlan, items: list[dict]) -> AIPlan:
    content = copy.deepcopy(plan.content)
    content["items"] = sorted(items, key=lambda value: value["start"])
    return AIPlan(
        user_id=plan.user_id,
        plan_date=plan.plan_date,
        revision=plan.revision + 1,
        source=plan.source,
        is_fallback=plan.is_fallback,
        fallback_reason=plan.fallback_reason,
        content=content,
    )


def remove_item(db: Session, user: User, plan_date: date, item_key: str, base_revision: int | None) -> AIPlan:
    """Remove one block from the latest plan for today or a later day, as a new revision."""
    lock_planning_state(db, user.id)
    if plan_date < local_now(user.profile.timezone).date():
        raise ManualItemInvalidError("Past plans are history and can't be changed.")
    current = _latest(db, user.id, plan_date)
    if current is None:
        raise NotFoundError("Plan")
    if base_revision is not None and current.revision != base_revision:
        raise ManualItemConflictError("Your plan changed. Refresh it and try again; nothing was removed.", "plan_stale")
    items = _keyed_items(current)
    target = next((item for item in items if item["item_key"] == item_key), None)
    if target is None:
        raise ManualItemConflictError(
            "This block is no longer in the latest plan. Refresh the plan and try again.", "plan_item_stale"
        )
    plan = _revision(current, [item for item in items if item is not target])
    db.add(plan)
    db.commit()
    db.refresh(plan)
    metrics.record("plan.item_removed", category=target["category"], manual=is_manual(target))
    return plan


def _range(item: dict) -> str:
    return f"{item['start']}–{item['end']}"


def add_item(db: Session, user: User, plan_date: date, body: ManualPlanItemIn) -> tuple[AIPlan, bool]:
    """Add one block as a new plan revision. Returns (plan, created_new_day)."""
    lock_planning_state(db, user.id)
    now = local_now(user.profile.timezone)
    today = now.date()
    if plan_date < today:
        raise ManualItemInvalidError("Blocks can only be added to today or a later day.")
    if plan_date > today + timedelta(days=MAX_DAYS_AHEAD):
        raise ManualItemInvalidError(f"Blocks can be added up to {MAX_DAYS_AHEAD} days ahead.")
    start = minutes(body.start)
    end = start + body.duration_minutes
    if end > DAY_MINUTES - 1:
        raise ManualItemInvalidError("The block must end by 23:59 on the same day.")
    if plan_date == today and start < now.hour * 60 + now.minute:
        raise ManualItemInvalidError("That time has already passed today. Choose a later start.")

    title = body.title
    task_id = subject_id = None
    if body.category == "task":
        task = db.scalar(select(Task).where(Task.id == body.task_id, Task.user_id == user.id))
        if task is None:
            raise NotFoundError("Task")
        if task.status == "done":
            raise ManualItemInvalidError("This task is already done.")
        title, task_id = task.title, task.id
    elif body.category == "study":
        subject = db.scalar(select(Subject).where(Subject.id == body.subject_id, Subject.user_id == user.id))
        if subject is None:
            raise NotFoundError("Subject")
        title, subject_id = subject.name, subject.id

    current = _latest(db, user.id, plan_date)
    if body.base_revision is not None and (current is None or current.revision != body.base_revision):
        raise ManualItemConflictError("Your plan changed. Refresh it and try again.", "plan_stale")
    items = _keyed_items(current) if current else []
    if len(items) >= MAX_ITEMS:
        raise ManualItemInvalidError(f"A day can hold at most {MAX_ITEMS} blocks.")
    if task_id is not None:
        same = next((item for item in items if str(item.get("task_id")) == str(task_id)), None)
        if same is not None:
            raise ManualItemInvalidError(f"{same['title']} is already in this plan at {same['start']}.")

    overlaps = [
        {"kind": "plan_block", "title": item["title"], "start": item["start"], "end": item["end"]}
        for item in items
        if start < minutes(item["end"]) and end > minutes(item["start"])
    ] + [
        {
            "kind": "commitment",
            "title": row.title,
            "start": hhmm(row.start_minutes),
            "end": hhmm(row.end_minutes),
        }
        for row in for_day(list_owned(db, user.id), plan_date)
        if start < row.end_minutes and end > row.start_minutes
    ]
    if overlaps:
        first = overlaps[0]
        more = f" and {len(overlaps) - 1} more" if len(overlaps) > 1 else ""
        metrics.record("plan.manual_item", result="conflict", category=body.category)
        raise ManualItemConflictError(
            f"This overlaps {first['title']} ({_range(first)}){more}. Nothing was moved; choose another time.",
            "plan_item_conflict",
            overlaps,
        )

    item = PlanItemOut(
        item_key=uuid.uuid4().hex,
        start=body.start,
        end=hhmm(end),
        category=body.category,
        title=title[:120],
        task_id=task_id,
        subject_id=subject_id,
        manual=True,
    ).model_dump(mode="json", exclude={"outcome", "outcome_minutes"})
    if current is not None:
        plan = _revision(current, [*items, item])
    else:
        profile = user.profile
        content = {
            "planning_start_minutes": profile.planning_start_minutes,
            "planning_end_minutes": profile.planning_end_minutes,
            "validation_version": 1,
            "window_start": hhmm(profile.planning_start_minutes),
            "window_end": hhmm(profile.planning_end_minutes),
            "assumptions": [],
            "unscheduled": [],
            "explanation": None,
            "summary": "Blocks you added to this day.",
            "items": [item],
            "tips": [],
            "adjustments": [],
        }
        plan = AIPlan(user_id=user.id, plan_date=plan_date, revision=1, source="manual", content=content)
    db.add(plan)
    db.commit()
    db.refresh(plan)
    metrics.record("plan.manual_item", result="added", category=body.category)
    return plan, current is None
