from datetime import date

from pydantic import BaseModel


class StreakOut(BaseModel):
    current: int
    longest: int
    active_today: bool


class Streaks(BaseModel):
    study: StreakOut
    tasks: StreakOut
    fitness: StreakOut
    balance: StreakOut


class DayProgress(BaseModel):
    date: date
    study_minutes: int
    tasks_completed: int
    steps: int
    workout_done: bool
    balanced: bool
    sleep_minutes: int | None = None
    calories: int = 0


class ProgressOut(BaseModel):
    date: date
    streaks: Streaks
    history: list[DayProgress]
