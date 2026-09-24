import uuid
from datetime import date
from typing import Literal

from pydantic import BaseModel

from app.modules.ai.schemas import AIPlanOut
from app.modules.progress.schemas import Streaks
from app.modules.study.schemas import PlanBlock
from app.modules.tasks.schemas import TaskOut


class TodaySummary(BaseModel):
    study_minutes: int
    study_goal_minutes: int
    tasks_completed: int
    task_goal: int
    steps: int
    step_goal: int
    workout_status: Literal["done", "pending"]
    workout_minutes: int = 0
    sleep_minutes: int | None = None
    sleep_goal_minutes: int = 480
    calories: int = 0
    calorie_goal: int = 2000


class NextExam(BaseModel):
    id: uuid.UUID
    title: str
    subject_name: str
    exam_date: date
    days_left: int


class DashboardOut(BaseModel):
    date: date
    greeting: Literal["morning", "afternoon", "evening"]
    display_name: str
    today: TodaySummary
    streaks: Streaks
    next_exam: NextExam | None
    upcoming_tasks: list[TaskOut]
    study_today: list[PlanBlock]
    ai_plan: AIPlanOut | None
