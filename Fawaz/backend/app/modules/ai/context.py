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
    ContextExam,
    ContextSleep,
    ContextStreak,
    ContextStudyBlock,
    ContextTask,
    DayStats,
    PlanContext,
)
from app.modules.progress.service import compute_streaks, daily_facts
from app.modules.progress.streaks import DayFacts
from app.modules.sleep.service import get_day as sleep_on
from app.modules.study import service as study_service
from app.modules.tasks.service import open_tasks_for_planning
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
    study_blocks = [
        ContextStudyBlock(subject=b.subject_name, title=b.title[:TITLE_LIMIT], minutes=b.minutes, reason=b.reason)
        for b in plan_today.blocks
    ]

    refs: dict[str, uuid.UUID] = {}
    tasks = []
    for n, task in enumerate(open_tasks_for_planning(db, user.id, limit=MAX_TASKS), start=1):
        ref = f"t{n}"
        refs[ref] = task.id
        tasks.append(
            ContextTask(
                ref=ref,
                title=task.title[:TITLE_LIMIT],
                priority=task.priority,
                due_in_days=(task.due_date - today).days if task.due_date else None,
            )
        )

    sleep = sleep_on(db, user.id, today)
    context = PlanContext(
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
    )
    return context, refs
