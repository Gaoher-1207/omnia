from collections import Counter
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.time import local_today, to_local_date
from app.modules.activity.service import get_range
from app.modules.nutrition.service import daily_totals
from app.modules.progress.achievements import AchievementOut
from app.modules.progress.achievements import compute as compute_achievements
from app.modules.progress.schemas import DayProgress, ProgressOut, StreakOut, Streaks
from app.modules.progress.streaks import DayFacts, current_streak, longest_streak
from app.modules.sleep.service import get_range as get_sleep_range
from app.modules.study.service import minutes_by_day
from app.modules.tasks.models import Task
from app.modules.users.models import User

STREAK_LOOKBACK_DAYS = 365


def tasks_completed_by_day(db: Session, user: User, start: date, end: date) -> dict[date, int]:
    tz = user.profile.timezone
    window_start = datetime.combine(start - timedelta(days=1), time.min, tzinfo=ZoneInfo(tz))
    moments = db.scalars(
        select(Task.completed_at).where(
            Task.user_id == user.id, Task.status == "done", Task.completed_at >= window_start
        )
    )
    counts = Counter(to_local_date(m, tz) for m in moments if m is not None)
    return {d: n for d, n in counts.items() if start <= d <= end}


def daily_facts(db: Session, user: User, start: date, end: date) -> dict[date, DayFacts]:
    study = minutes_by_day(db, user.id, start, end)
    tasks = tasks_completed_by_day(db, user, start, end)
    activity = get_range(db, user.id, start, end)
    facts = {}
    day = start
    while day <= end:
        act = activity.get(day)
        facts[day] = DayFacts(
            day=day,
            study_minutes=study.get(day, 0),
            tasks_completed=tasks.get(day, 0),
            steps=act.steps if act else 0,
            workout_done=act.workout_done if act else False,
        )
        day += timedelta(days=1)
    return facts


def _streak(active: set[date], today: date) -> StreakOut:
    return StreakOut(
        current=current_streak(active, today),
        longest=longest_streak(active),
        active_today=today in active,
    )


def compute_streaks(facts: dict[date, DayFacts], today: date, step_goal: int) -> Streaks:
    values = facts.values()
    return Streaks(
        study=_streak({f.day for f in values if f.study_active()}, today),
        tasks=_streak({f.day for f in values if f.tasks_active()}, today),
        fitness=_streak({f.day for f in values if f.fitness_active(step_goal)}, today),
        balance=_streak({f.day for f in values if f.balanced(step_goal)}, today),
    )


def progress(db: Session, user: User, history_days: int = 14) -> ProgressOut:
    today = local_today(user.profile.timezone)
    step_goal = user.profile.daily_step_goal
    facts = daily_facts(db, user, today - timedelta(days=STREAK_LOOKBACK_DAYS - 1), today)
    history_start = today - timedelta(days=history_days - 1)
    sleep = get_sleep_range(db, user.id, history_start, today)
    calories = {d.day: d.calories for d in daily_totals(db, user.id, history_start, today)}
    history = [
        DayProgress(
            date=f.day,
            study_minutes=f.study_minutes,
            tasks_completed=f.tasks_completed,
            steps=f.steps,
            workout_done=f.workout_done,
            balanced=f.balanced(step_goal),
            sleep_minutes=sleep[f.day].duration_minutes if f.day in sleep else None,
            calories=calories.get(f.day, 0),
        )
        for f in facts.values()
        if f.day >= history_start
    ]
    return ProgressOut(date=today, streaks=compute_streaks(facts, today, step_goal), history=history)


def achievements(db: Session, user: User) -> list[AchievementOut]:
    today = local_today(user.profile.timezone)
    start = today - timedelta(days=STREAK_LOOKBACK_DAYS - 1)
    facts = daily_facts(db, user, start, today)
    sleep = {d: row.duration_minutes for d, row in get_sleep_range(db, user.id, start, today).items()}
    return compute_achievements(facts, user.profile.daily_step_goal, sleep, user.profile.daily_sleep_goal_minutes)
