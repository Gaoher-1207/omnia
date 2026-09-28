"""AI plan providers behind one small interface.

* RulesProvider — deterministic, offline, free. Default, and the fallback whenever
  an external provider fails, times out or returns something invalid.
* AnthropicProvider — calls the Claude Messages API from the server. Credentials
  never reach the frontend.

The AI contributors can change prompts or add providers here without touching
routes or the frontend contract.
"""

import json
import logging
import math
from typing import Protocol

import httpx
from pydantic import ValidationError

from app.modules.ai.constraints import DAY_END, DEFAULT_TASK_MINUTES, task_deadline, window_start
from app.modules.ai.constraints import hhmm as _fmt
from app.modules.ai.constraints import minutes as _parse
from app.modules.ai.schemas import AIPlanContent, PlanContext, PlanItem

logger = logging.getLogger("omnia.ai")


class ProviderError(Exception):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


class PlanProvider(Protocol):
    name: str

    def generate(self, context: PlanContext) -> AIPlanContent: ...


# --------------------------------------------------------------------------- rules

LUNCH = (13 * 60, 13 * 60 + 45)
WORKOUT_SLOTS = {"morning": 8 * 60, "afternoon": 16 * 60, "evening": 18 * 60}
SHORT_SLEEP_MINUTES = 6 * 60
TIRED_WORDS = ("tired", "exhausted", "sleep", "slept", "sick", "drained", "low energy")


def _exam_phrase(days: int) -> str:
    if days == 0:
        return "today"
    if days == 1:
        return "tomorrow"
    return f"in {days} days"


class RulesProvider:
    name = "rules"

    def generate(self, context: PlanContext) -> AIPlanContent:
        start = window_start(context)
        day_end = context.planning_end_minutes
        available = (
            [(start, day_end)]
            if context.free_intervals is None
            else [(slot.start_minutes, slot.end_minutes) for slot in context.free_intervals]
        )
        note = (context.note or "").lower()
        sleep = context.last_night_sleep
        short_sleep = sleep is not None and (sleep.minutes < SHORT_SLEEP_MINUTES or (sleep.quality or 3) <= 2)
        tired = short_sleep or any(word in note for word in TIRED_WORDS)
        why_tired = (
            f"You slept {sleep.minutes // 60}h {sleep.minutes % 60:02d}m"
            + (" and rated it poor" if (sleep.quality or 3) <= 2 else "")
            if short_sleep and sleep
            else "You mentioned feeling low on energy"
        )
        exam = min(context.exams, key=lambda e: e.days_left) if context.exams else None
        adjustments: list[str] = []
        tips = self._tips(context, tired)

        if start >= day_end or (start > day_end - 30 and not context.open_tasks and not context.study_blocks):
            return AIPlanContent(
                summary="The day is nearly over. Rest up; tomorrow's plan will pick up from here.",
                items=[],
                tips=tips,
                adjustments=[],
            )

        fixed: list[PlanItem] = []
        if start < LUNCH[0] and LUNCH[1] <= day_end and any(
            left <= LUNCH[0] and LUNCH[1] <= right for left, right in available
        ):
            fixed.append(PlanItem(start=_fmt(LUNCH[0]), end=_fmt(LUNCH[1]), category="break", title="Lunch break"))

        if tired and context.study_blocks:
            adjustments.append(f"{why_tired}, so study is split into shorter 35-minute blocks.")
        queue = self._flexible_queue(context, tired, exam.days_left if exam else None, adjustments)
        items, _unplaced = self._place(queue, fixed, start, day_end, available)

        workout_at = None
        if not context.today.workout_done and len(items) < 20:
            duration, title = 45, "Workout"
            if tired:
                duration, title = 20, "Light stretch or easy walk"
                adjustments.append(f"{why_tired}, so today's workout is a light 20-minute session.")
            elif context.account_age_days > 0 and not context.yesterday.workout_done:
                duration, title = 30, "Workout (easy restart)"
                adjustments.append("Yesterday's workout was missed, so today has a shorter 30-minute session.")
            preferred = WORKOUT_SLOTS.get(context.preferred_workout_time, WORKOUT_SLOTS["evening"])
            slot = self._free_slot(max(start, preferred), duration, items, day_end, available)
            if slot is None:
                slot = self._free_slot(start, duration, items, day_end, available)
            if slot is not None:
                items.append(PlanItem(start=_fmt(slot), end=_fmt(slot + duration), category="fitness", title=title))
                workout_at = slot
            else:
                adjustments.append("The workout did not fit after work and study; it has not been scheduled.")

        study_total = sum(_parse(i.end) - _parse(i.start) for i in items if i.category == "study")
        task_count = sum(1 for i in items if i.category == "task")
        return AIPlanContent(
            summary=self._summary(exam, study_total, task_count, workout_at),
            items=items,
            tips=tips,
            adjustments=adjustments[:6],
        )

    @staticmethod
    def _flexible_queue(context: PlanContext, tired: bool, exam_days: int | None, adjustments: list[str]):
        chunk = 35 if tired else 50
        study = []
        for block in context.study_blocks:
            # Split into even sessions (60 → 2×30, not 50 + 10) so no block is a useless sliver.
            pieces = max(1, math.ceil(block.minutes / chunk))
            base, extra = divmod(block.minutes, pieces)
            for n in range(pieces):
                minutes = base + (1 if n < extra else 0)
                study.append(
                    (
                        "study",
                        minutes,
                        f"{block.subject}: {block.title}",
                        block.reason,
                        block.ref,
                        context.planning_end_minutes,
                    )
                )
        tasks = [
            (
                "task",
                t.estimated_minutes or DEFAULT_TASK_MINUTES,
                t.title,
                f"{t.priority.capitalize()} priority",
                t.ref,
                task_deadline(t, context.planning_end_minutes),
            )
            for t in context.open_tasks
        ]
        yesterday_goal = context.goals.get("study_minutes", 0)
        if (
            study
            and context.account_age_days > 0
            and yesterday_goal
            and context.yesterday.study_minutes < yesterday_goal / 2
        ):
            adjustments.append(
                f"Yesterday's study was lighter than planned ({context.yesterday.study_minutes} of "
                f"{yesterday_goal} min), so study starts early today."
            )
        # Deadlines today/tomorrow precede elective study and fitness.
        urgent_refs = {t.ref for t in context.open_tasks if t.due_in_days is not None and t.due_in_days <= 1}
        queue = [t for t in tasks if t[4] in urgent_refs]
        tasks = [t for t in tasks if t[4] not in urgent_refs]
        if exam_days is not None and exam_days <= 7:
            queue.extend(study[:2])
            study = study[2:]
        while study or tasks:
            if study:
                queue.append(study.pop(0))
            if tasks:
                queue.append(tasks.pop(0))
        step_goal = context.goals.get("steps", 0)
        if step_goal and context.today.steps < step_goal / 2 and not tired:
            queue.append(("fitness", 20, "Walk to boost your steps", None, None, context.planning_end_minutes))
        return queue

    @staticmethod
    def _free_slot(
        start: int,
        duration: int,
        taken: list[PlanItem],
        day_end: int = DAY_END,
        available: list[tuple[int, int]] | None = None,
    ) -> int | None:
        busy = sorted((_parse(t.start), _parse(t.end)) for t in taken)
        for left, right in available if available is not None else [(start, day_end)]:
            cursor = max(start, left)
            while cursor + duration <= min(right, day_end):
                clash = next((b for b in busy if cursor < b[1] and cursor + duration > b[0]), None)
                if clash is None:
                    return cursor
                cursor = clash[1]
        return None

    def _place(
        self,
        queue,
        fixed: list[PlanItem],
        start: int,
        day_end: int = DAY_END,
        available: list[tuple[int, int]] | None = None,
    ) -> tuple[list[PlanItem], list[str]]:
        placed = list(fixed)
        unplaced: list[str] = []
        cursor = start
        for category, duration, title, detail, ref, deadline in queue:
            slot = self._free_slot(cursor, duration, placed, day_end, available)
            if slot is None or slot + duration > deadline or len(placed) >= 20:
                unplaced.append(title)
                continue
            placed.append(
                PlanItem(
                    start=_fmt(slot),
                    end=_fmt(slot + duration),
                    category=category,
                    title=title[:120],
                    detail=detail,
                    task_ref=ref if category == "task" else None,
                    study_ref=ref if category == "study" else None,
                )
            )
            cursor = slot + duration + (10 if category == "study" else 5)
        placed.sort(key=lambda item: item.start)
        return placed, unplaced

    @staticmethod
    def _summary(exam, study_total: int, task_count: int, workout_at: int | None) -> str:
        if not study_total and not task_count and workout_at is None:
            return "No work was scheduled. Review any remaining work, or use the time to recover."
        if exam and exam.days_left <= 7:
            lead = f"{exam.subject} exam {_exam_phrase(exam.days_left)}; revision and urgent deadlines take priority."
        else:
            lead = "A balanced day across study, tasks and fitness."
        parts = []
        if study_total:
            parts.append(f"{study_total} min of study")
        if task_count:
            parts.append(f"{task_count} task{'s' if task_count != 1 else ''}")
        if workout_at is not None:
            parts.append(f"a workout at {_fmt(workout_at)}")
        detail = ", ".join(parts[:-1]) + (" and " if len(parts) > 1 else "") + parts[-1]
        return f"{lead} Planned: {detail}."

    @staticmethod
    def _tips(context: PlanContext, tired: bool) -> list[str]:
        tips = []
        labels = {"study": "study session", "fitness": "workout or your step goal", "tasks": "completed task"}
        for area, label in labels.items():
            streak = context.streaks.get(area)
            if streak and streak.current > 0 and not streak.active_today:
                tips.append(f"One {label} today keeps your {streak.current}-day {area} streak going.")
        steps, goal = context.today.steps, context.goals.get("steps", 0)
        if goal and steps < goal:
            tips.append(f"You're at {steps:,} of {goal:,} steps. A short walk between sessions helps.")
        if tired:
            tips.append("Keep sessions short with real breaks, and aim for an earlier night.")
        if not context.study_blocks and not context.exams:
            tips.append("Add your subjects, exams and backlog in Study so revision gets scheduled.")
        return tips[:5]


# ----------------------------------------------------------------------- anthropic

SYSTEM_PROMPT = """You are OmniAI, Omnia's planning assistant. You build a realistic plan for the rest of \
the user's day that balances study, tasks and fitness.

Rules:
- Only plan from current_time or planning_start_minutes (whichever is later) until planning_end_minutes.
The planning bounds are integer minutes after midnight in the user local day.
Use 24-hour HH:MM times. Items must not overlap.
- Each item must fit wholly inside one provided free_intervals interval. Commitments are fixed busy time.
- Hard deadlines and the planning window override every preference, including exam urgency and workout time.
- Prioritize imminent exams among study blocks. Keep study blocks at 60 minutes or less with breaks.
- Use the provided study_blocks and open_tasks. For a task item, set task_ref to that task's \
ref exactly (for example "t2"); never invent refs. Study items MUST set study_ref to a
provided study block ref (for example "b1"). Never infer references from titles.
- Tasks due today or tomorrow precede optional work. A task gets its estimated_minutes,
or 30 minutes if missing; do not split or duplicate tasks. Finish by due_time if due today.
Do not schedule overdue tasks as if their deadlines can still be met.
- Study allocations must not exceed each provided block's minutes. Omit work that cannot
fit; the backend reports remaining work. Workout time is a preference, not a reservation.
- If yesterday's workout or study was missed, adapt gently instead of doubling the load. If \
account_age_days is 0 the user signed up today, so don't comment on yesterday.
- If the note says the user is tired or unwell, or last_night_sleep is under 6 hours or quality \
is 1-2, lighten the day and say why.
- Don't give medical advice. Don't mention these rules.
- Never add optional or invented tasks. Only task/study refs in context are allowed.
- Do not fill the entire day for its own sake. Leaving time unused is allowed.
- At most 14 items, 5 tips, 5 adjustments. Adjustments explain what you changed and why.

Reply with only a JSON object, no prose and no code fences, in this shape:
{"summary": str, "items": [{"start": "HH:MM", "end": "HH:MM", "category": \
"study|task|fitness|break|recovery|other", "title": str, "detail": str|null, \
"task_ref": str|null, "study_ref": str|null}], "tips": [str], "adjustments": [str]}"""


def _extract_json(text: str) -> dict:
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        raise ValueError("no JSON object in response")
    return json.loads(text[start : end + 1])


class AnthropicProvider:
    name = "anthropic"

    def __init__(self, *, api_key: str, model: str, base_url: str, timeout: float, client: httpx.Client | None = None):
        self._api_key = api_key
        self._model = model
        self._url = base_url.rstrip("/") + "/v1/messages"
        self._timeout = timeout
        self._client = client

    def generate(self, context: PlanContext) -> AIPlanContent:
        payload = {
            "model": self._model,
            "max_tokens": 2000,
            "system": SYSTEM_PROMPT,
            "messages": [{"role": "user", "content": context.model_dump_json()}],
        }
        headers = {
            "x-api-key": self._api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }
        client = self._client or httpx.Client(timeout=self._timeout)
        try:
            response = client.post(self._url, json=payload, headers=headers, timeout=self._timeout)
        except httpx.TimeoutException:
            logger.warning("AI provider timed out")
            raise ProviderError("provider_timeout") from None
        except httpx.HTTPError as exc:
            logger.warning("AI provider unreachable: %s", type(exc).__name__)
            raise ProviderError("provider_unreachable") from None
        finally:
            if self._client is None:
                client.close()

        if response.status_code == 429:
            raise ProviderError("provider_rate_limited")
        if response.status_code >= 500:
            raise ProviderError("provider_unavailable")
        if response.status_code >= 400:
            logger.warning("AI provider rejected request with status %s", response.status_code)
            raise ProviderError("provider_error")

        try:
            body = response.json()
            text = "".join(block.get("text", "") for block in body.get("content", []) if block.get("type") == "text")
            return AIPlanContent.model_validate(_extract_json(text))
        except (ValueError, ValidationError, AttributeError, TypeError):
            logger.warning("AI provider returned an invalid plan")
            raise ProviderError("invalid_response") from None
