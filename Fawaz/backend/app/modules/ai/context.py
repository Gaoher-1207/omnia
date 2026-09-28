"""Builds the minimal context an AI provider sees.

Included: goals, today's and yesterday's totals, streak counts, upcoming exams,
today's study blocks, open task titles, and the optional note the user typed.
Never included: email, name, account ids, task notes, timezone, or history
beyond yesterday. Task ids are replaced with short refs (t1, t2…) and mapped
back on the server, so a provider can't reference anything it wasn't given.
"""

import uuid
from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.core.time import to_local_date
from app.modules.ai.schemas import (
    ContextCommitment,
    ContextExam,
    ContextSleep,
    ContextStreak,
    ContextStudyBlock,
    ContextTask,
    DayStats,
    PlanContext,
)
from app.modules.commitments.service import availability
from app.modules.progress.service import compute_streaks, daily_facts
from app.modules.progress.streaks import DayFacts
from app.modules.sleep.service import get_day as sleep_on
from app.modules.study import service as study_service
from app.modules.tasks.service import list_tasks
from app.modules.users.models import User

MAX_TASKS = 10
MAX_EXAMS = 5
EXAM_WINDOW_DAYS = 30
TITLE_LIMIT = 80


def _stats(f: DayFacts) -> DayStats:
    return DayStats(
        study_minutes=f.study_minutes,
        tasks_completed=f.tasks_completed,
        steps=f.steps,
        workout_done=f.workout_done,
    )


def build_context(
    db: Session, user: User, now_local: datetime, note: str | None
) -> tuple[PlanContext, dict[str, uuid.UUID]]:
    profile = user.profile
    today = now_local.date()
    facts = daily_facts(db, user, today - timedelta(days=60), today)
    streaks = compute_streaks(facts, today, profile.daily_step_goal)

    exams = [
        ContextExam(subject=e.subject.name, title=e.title[:TITLE_LIMIT], days_left=(e.exam_date - today).days)
        for e in study_service.list_exams(db, user.id, include_past=False, today=today)
        if (e.exam_date - today).days <= EXAM_WINDOW_DAYS
    ][:MAX_EXAMS]

    plan_today = study_service.study_plan(db, user, days=1).days[0]
    refs: dict[str, uuid.UUID] = {f"b{n}": b.subject_id for n, b in enumerate(plan_today.blocks, start=1)}
    study_blocks = [
        ContextStudyBlock(
            ref=f"b{n}", subject=b.subject_name, title=b.title[:TITLE_LIMIT], minutes=b.minutes, reason=b.reason
        )
        for n, b in enumerate(plan_today.blocks, start=1)
    ]

    tasks = []
    selected, total = list_tasks(
        db, user.id, status="todo", priority=None, due_on_or_before=None, limit=MAX_TASKS, offset=0
    )
    for n, task in enumerate(selected, start=1):
        ref = f"t{n}"
        refs[ref] = task.id
        tasks.append(
            ContextTask(
                ref=ref,
                title=task.title[:TITLE_LIMIT],
                priority=task.priority,
                due_in_days=(task.due_date - today).days if task.due_date else None,
                due_time=task.due_time.strftime("%H:%M") if task.due_time else None,
                estimated_minutes=task.estimated_minutes,
            )
        )

    sleep = sleep_on(db, user.id, today)
    applicable, _busy, free = availability(
        db,
        user.id,
        today,
        max(profile.planning_start_minutes, now_local.hour * 60 + now_local.minute),
        profile.planning_end_minutes,
    )
    context = PlanContext(
        planning_start_minutes=profile.planning_start_minutes,
        planning_end_minutes=profile.planning_end_minutes,
        free_intervals=free,
        commitments=[
            ContextCommitment(
                title=row.title,
                category=row.category,
                start_minutes=row.start_minutes,
                end_minutes=row.end_minutes,
            )
            for row in applicable
        ],
        date=today,
        weekday=today.strftime("%A"),
        current_time=now_local.strftime("%H:%M"),
        goals={
            "study_minutes": profile.daily_study_goal_minutes,
            "steps": profile.daily_step_goal,
            "tasks": profile.daily_task_goal,
            "sleep_minutes": profile.daily_sleep_goal_minutes,
        },
        preferred_workout_time=profile.preferred_workout_time,
        today=_stats(facts[today]),
        yesterday=_stats(facts[today - timedelta(days=1)]),
        streaks={
            name: ContextStreak(
                current=getattr(streaks, name).current,
                active_today=getattr(streaks, name).active_today,
            )
            for name in ("study", "tasks", "fitness", "balance")
        },
        exams=exams,
        study_blocks=study_blocks,
        open_tasks=tasks,
        note=note.strip() if note and note.strip() else None,
        account_age_days=(today - to_local_date(user.created_at, profile.timezone)).days,
        last_night_sleep=ContextSleep(minutes=sleep.duration_minutes, quality=sleep.quality) if sleep else None,
        omitted_tasks=max(0, total - len(selected)),
    )
    return context, refs
