"""Study planner: spreads pending backlog/revision work across the next few days.

Pure logic with no database access, so it is easy to test and easy for the AI
contributors to replace or tune. Rules (all adjustable, pending team review):

* Each day gets the user's daily study goal (today: minus what is already logged).
* Items for subjects with a closer exam come first; backlog before revision.
* One subject takes at most 60% of a day when others are waiting, for balance.
* On an exam day that subject only gets a short light review.
* Time left over goes to general revision for exams in the next 14 days
  (up to 90 min per subject in the final week, 45 min before that).
* If a subject's backlog can't fit before its exam, the plan says so plainly.
"""

import math
import uuid
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta

from app.modules.study.schemas import PlanBlock, PlanDay, PlanExam, StudyPlanOut

MIN_BLOCK = 15
SUBJECT_SHARE = 0.6
EXAM_DAY_REVIEW_CAP = 45
GENERAL_REVISION_BLOCK = 45
GENERAL_REVISION_WINDOW_DAYS = 14


@dataclass(frozen=True)
class PlannerExam:
    id: uuid.UUID
    subject_id: uuid.UUID
    title: str
    exam_date: date


@dataclass(frozen=True)
class PlannerItem:
    id: uuid.UUID
    subject_id: uuid.UUID
    title: str
    kind: str
    minutes: int
    order: int


def _days_label(days: int) -> str:
    if days == 0:
        return "Exam today — light review"
    if days == 1:
        return "Exam tomorrow"
    return f"Exam in {days} days"


def build_study_plan(
    *,
    start: date,
    days: int,
    daily_minutes: int,
    studied_today: int,
    subjects: dict[uuid.UUID, str],
    exams: list[PlannerExam],
    items: list[PlannerItem],
) -> StudyPlanOut:
    exams = [e for e in exams if e.exam_date >= start and e.subject_id in subjects]
    items = [i for i in items if i.subject_id in subjects]
    remaining = {i.id: i.minutes for i in items}
    item_minutes: dict[tuple[uuid.UUID, date], int] = defaultdict(int)
    plan_days: list[PlanDay] = []

    def next_exam_days(subject_id: uuid.UUID, day: date) -> int | None:
        upcoming = [(e.exam_date - day).days for e in exams if e.subject_id == subject_id and e.exam_date >= day]
        return min(upcoming) if upcoming else None

    for offset in range(days):
        day = start + timedelta(days=offset)
        available = max(0, daily_minutes - (studied_today if offset == 0 else 0))
        used = 0
        per_subject: dict[uuid.UUID, int] = defaultdict(int)
        blocks: list[PlanBlock] = []

        def score(item: PlannerItem, _day: date = day) -> tuple[float, int]:
            days_to = next_exam_days(item.subject_id, _day)
            urgency = 1000 / (days_to + 1) if days_to is not None else 5
            kind_bonus = 2 if item.kind == "backlog" else 1
            return (-(urgency + kind_bonus), item.order)

        def subject_cap(subject_id: uuid.UUID, share_cap: int, _day: date = day) -> int:
            if next_exam_days(subject_id, _day) == 0:
                return min(share_cap, EXAM_DAY_REVIEW_CAP)
            return share_cap

        for use_share in (True, False):
            candidates = sorted((i for i in items if remaining[i.id] > 0), key=score)
            waiting_subjects = {i.subject_id for i in candidates}
            share_cap = (
                max(MIN_BLOCK, math.ceil(available * SUBJECT_SHARE))
                if use_share and len(waiting_subjects) > 1
                else available
            )
            for item in candidates:
                left = available - used
                if left < MIN_BLOCK:
                    break
                cap = subject_cap(item.subject_id, share_cap) - per_subject[item.subject_id]
                minutes = min(remaining[item.id], left, cap)
                if minutes < MIN_BLOCK and minutes != remaining[item.id]:
                    continue
                if minutes <= 0:
                    continue
                days_to = next_exam_days(item.subject_id, day)
                reason = (
                    _days_label(days_to)
                    if days_to is not None
                    else ("Clearing backlog" if item.kind == "backlog" else "Revision")
                )
                blocks.append(
                    PlanBlock(
                        subject_id=item.subject_id,
                        subject_name=subjects[item.subject_id],
                        backlog_item_id=item.id,
                        title=item.title,
                        minutes=minutes,
                        reason=reason,
                    )
                )
                remaining[item.id] -= minutes
                per_subject[item.subject_id] += minutes
                item_minutes[(item.subject_id, day)] += minutes
                used += minutes

        upcoming = sorted(
            (e for e in exams if 1 <= (e.exam_date - day).days <= GENERAL_REVISION_WINDOW_DAYS),
            key=lambda e: e.exam_date,
        )
        seen: set[uuid.UUID] = set()
        for exam in upcoming:
            left = available - used
            if left < MIN_BLOCK:
                break
            if exam.subject_id in seen:
                continue
            seen.add(exam.subject_id)
            days_to = (exam.exam_date - day).days
            block = GENERAL_REVISION_BLOCK * (2 if days_to <= 7 else 1)
            minutes = min(block, left)
            blocks.append(
                PlanBlock(
                    subject_id=exam.subject_id,
                    subject_name=subjects[exam.subject_id],
                    backlog_item_id=None,
                    title="General revision",
                    minutes=minutes,
                    reason=_days_label((exam.exam_date - day).days),
                )
            )
            per_subject[exam.subject_id] += minutes
            used += minutes

        plan_days.append(
            PlanDay(
                date=day,
                available_minutes=available,
                planned_minutes=used,
                blocks=blocks,
                exams=[
                    PlanExam(exam_id=e.id, subject_name=subjects[e.subject_id], title=e.title)
                    for e in exams
                    if e.exam_date == day
                ],
            )
        )

    warnings: list[str] = []
    if daily_minutes == 0:
        warnings.append("Your daily study goal is 0 minutes, so nothing can be scheduled.")
    horizon_end = start + timedelta(days=days)
    for exam in sorted(exams, key=lambda e: e.exam_date):
        if exam.exam_date >= horizon_end:
            continue
        needed = sum(i.minutes for i in items if i.subject_id == exam.subject_id)
        got = sum(
            minutes
            for (subject_id, day), minutes in item_minutes.items()
            if subject_id == exam.subject_id and day < exam.exam_date
        )
        if needed > got:
            warnings.append(
                f"{subjects[exam.subject_id]}: about {needed - got} min of pending work won't fit "
                f"before the exam on {exam.exam_date.isoformat()}. Consider a higher daily goal or "
                "trimming topics."
            )

    return StudyPlanOut(
        start_date=start,
        days=plan_days,
        unscheduled_minutes=sum(remaining.values()),
        warnings=warnings,
    )
