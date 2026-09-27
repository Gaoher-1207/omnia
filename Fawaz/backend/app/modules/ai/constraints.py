"""Deterministic checks shared by model proposals and the rules fallback.

This slice assumes one free window ending at 22:00. Calendar availability and
accepted/locked items must become explicit inputs before adaptive replanning.
"""

from collections import Counter

from app.modules.ai.schemas import AIPlanContent, ContextTask, PlanContext

DAY_START = 8 * 60
DAY_END = 22 * 60
DEFAULT_TASK_MINUTES = 30


def minutes(hhmm: str) -> int:
    hours, minute = hhmm.split(":")
    return int(hours) * 60 + int(minute)


def hhmm(value: int) -> str:
    return f"{value // 60:02d}:{value % 60:02d}"


def window_start(context: PlanContext) -> int:
    return min(DAY_END, max(DAY_START, minutes(context.current_time)))


def task_deadline(task: ContextTask) -> int:
    if task.due_in_days is not None and task.due_in_days < 0:
        return 0
    if task.due_in_days == 0 and task.due_time:
        return min(DAY_END, minutes(task.due_time))
    return DAY_END


def validate_candidate(content: AIPlanContent, context: PlanContext) -> AIPlanContent:
    # Reparse even objects returned by injected providers: never trust construction.
    checked = AIPlanContent.model_validate(content.model_dump() if isinstance(content, AIPlanContent) else content)
    tasks = {t.ref: t for t in context.open_tasks}
    blocks = {b.ref: b for b in context.study_blocks}
    used: Counter[str] = Counter()
    for item in checked.items:
        start, end = minutes(item.start), minutes(item.end)
        if start < window_start(context) or end > DAY_END:
            raise ValueError("outside_available_window")
        if item.category == "task":
            task = tasks.get(item.task_ref)
            if task is None or item.study_ref is not None or used[task.ref]:
                raise ValueError("invalid_task_reference")
            if end > task_deadline(task) or end - start != (task.estimated_minutes or DEFAULT_TASK_MINUTES):
                raise ValueError("task_duration_or_deadline")
            used[task.ref] += end - start
            item.title = task.title
        elif item.category == "study":
            block = blocks.get(item.study_ref)
            if block is None or item.task_ref is not None:
                raise ValueError("invalid_study_reference")
            used[block.ref] += end - start
            if used[block.ref] > block.minutes or end - start > 60:
                raise ValueError("study_budget_exceeded")
            item.title = f"{block.subject}: {block.title}"[:120]
        elif item.task_ref is not None or item.study_ref is not None:
            raise ValueError("reference_category_mismatch")
    return checked
