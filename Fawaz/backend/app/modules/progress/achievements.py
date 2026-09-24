"""Achievements: computed from the user's own records, never stored or client-supplied."""

from dataclasses import dataclass
from datetime import date

from pydantic import BaseModel

from app.modules.progress.streaks import DayFacts, longest_streak


@dataclass(frozen=True)
class Definition:
    code: str
    title: str
    description: str
    target: int


DEFINITIONS = [
    Definition("first_study", "First step", "Log your first study session", 1),
    Definition("study_streak_3", "Warming up", "Study 3 days in a row", 3),
    Definition("study_streak_7", "Week of focus", "Study 7 days in a row", 7),
    Definition("study_streak_30", "Unstoppable", "Study 30 days in a row", 30),
    Definition("balance_streak_7", "In balance", "7 balanced days in a row", 7),
    Definition("study_hours_10", "10 hours in", "Study 10 hours in total", 600),
    Definition("study_hours_50", "Deep work", "Study 50 hours in total", 3000),
    Definition("tasks_25", "Getting things done", "Complete 25 tasks", 25),
    Definition("tasks_100", "Task master", "Complete 100 tasks", 100),
    Definition("steps_10", "On the move", "Reach your step goal on 10 days", 10),
    Definition("workouts_10", "Ten workouts", "Log 10 workouts", 10),
    Definition("sleep_7", "Well rested", "Meet your sleep goal on 7 nights", 7),
]
BY_CODE = {d.code: d for d in DEFINITIONS}


class AchievementOut(BaseModel):
    code: str
    title: str
    description: str
    earned: bool
    progress: int
    target: int


def compute(
    facts: dict[date, DayFacts], step_goal: int, sleep_minutes: dict[date, int], sleep_goal: int
) -> list[AchievementOut]:
    days = list(facts.values())
    study_days = {f.day for f in days if f.study_active()}
    values = {
        "first_study": len(study_days),
        "study_streak_3": longest_streak(study_days),
        "study_streak_7": longest_streak(study_days),
        "study_streak_30": longest_streak(study_days),
        "balance_streak_7": longest_streak({f.day for f in days if f.balanced(step_goal)}),
        "study_hours_10": sum(f.study_minutes for f in days),
        "study_hours_50": sum(f.study_minutes for f in days),
        "tasks_25": sum(f.tasks_completed for f in days),
        "tasks_100": sum(f.tasks_completed for f in days),
        "steps_10": sum(1 for f in days if step_goal > 0 and f.steps >= step_goal),
        "workouts_10": sum(1 for f in days if f.workout_done),
        "sleep_7": sum(1 for m in sleep_minutes.values() if sleep_goal > 0 and m >= sleep_goal),
    }
    return [
        AchievementOut(
            code=d.code,
            title=d.title,
            description=d.description,
            earned=values[d.code] >= d.target,
            progress=min(values[d.code], d.target),
            target=d.target,
        )
        for d in DEFINITIONS
    ]
