from datetime import timedelta

from sqlalchemy.orm import Session

from app.core.time import local_now
from app.modules.activity.service import get_day as activity_on
from app.modules.ai.service import latest_plan, plan_out
from app.modules.dashboard.schemas import DashboardOut, NextExam, TodaySummary
from app.modules.nutrition.service import meals_on, totals
from app.modules.progress.service import STREAK_LOOKBACK_DAYS, compute_streaks, daily_facts
from app.modules.sleep.service import get_day as sleep_on
from app.modules.study import service as study_service
from app.modules.tasks.service import open_tasks_for_planning
from app.modules.users.models import User


def _greeting(hour: int) -> str:
    if hour < 12:
        return "morning"
    if hour < 17:
        return "afternoon"
    return "evening"


def dashboard(db: Session, user: User) -> DashboardOut:
    profile = user.profile
    now = local_now(profile.timezone)
    today = now.date()
    facts = daily_facts(db, user, today - timedelta(days=STREAK_LOOKBACK_DAYS - 1), today)
    today_facts = facts[today]

    exams = study_service.list_exams(db, user.id, include_past=False, today=today)
    next_exam = None
    if exams:
        exam = exams[0]
        next_exam = NextExam(
            id=exam.id,
            title=exam.title,
            subject_name=exam.subject.name,
            exam_date=exam.exam_date,
            days_left=(exam.exam_date - today).days,
        )

    plan = latest_plan(db, user.id, today)
    sleep = sleep_on(db, user.id, today)
    activity = activity_on(db, user.id, today)
    return DashboardOut(
        date=today,
        greeting=_greeting(now.hour),
        display_name=profile.display_name,
        today=TodaySummary(
            study_minutes=today_facts.study_minutes,
            study_goal_minutes=profile.daily_study_goal_minutes,
            tasks_completed=today_facts.tasks_completed,
            task_goal=profile.daily_task_goal,
            steps=today_facts.steps,
            step_goal=profile.daily_step_goal,
            workout_status="done" if today_facts.workout_done else "pending",
            workout_minutes=activity.workout_minutes if activity else 0,
            sleep_minutes=sleep.duration_minutes if sleep else None,
            sleep_goal_minutes=profile.daily_sleep_goal_minutes,
            calories=totals(meals_on(db, user.id, today)).calories,
            calorie_goal=profile.daily_calorie_goal,
        ),
        streaks=compute_streaks(facts, today, profile.daily_step_goal),
        next_exam=next_exam,
        upcoming_tasks=open_tasks_for_planning(db, user.id, limit=5),
        study_today=study_service.study_plan(db, user, days=1).days[0].blocks,
        ai_plan=plan_out(plan) if plan else None,
    )
