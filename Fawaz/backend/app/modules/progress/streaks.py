"""Streak rules (pure functions, pending product review).

A day counts for an area when:
* study   — at least one study session was logged
* tasks   — at least one task was completed
* fitness — a workout was logged, or the daily step goal was reached
* balance — at least two of the three areas above were active

A streak is the run of consecutive active days ending today. If today isn't
active yet the streak is still alive and counts up to yesterday, so users
aren't told they "lost" a streak at breakfast.
"""

from dataclasses import dataclass
from datetime import date, timedelta

BALANCE_MIN_AREAS = 2


@dataclass(frozen=True)
class DayFacts:
    day: date
    study_minutes: int = 0
    tasks_completed: int = 0
    steps: int = 0
    workout_done: bool = False

    def study_active(self) -> bool:
        return self.study_minutes > 0

    def tasks_active(self) -> bool:
        return self.tasks_completed > 0

    def fitness_active(self, step_goal: int) -> bool:
        return self.workout_done or (step_goal > 0 and self.steps >= step_goal)

    def balanced(self, step_goal: int) -> bool:
        active = [self.study_active(), self.tasks_active(), self.fitness_active(step_goal)]
        return sum(active) >= BALANCE_MIN_AREAS


def current_streak(active_days: set[date], today: date) -> int:
    day = today if today in active_days else today - timedelta(days=1)
    count = 0
    while day in active_days:
        count += 1
        day -= timedelta(days=1)
    return count


def longest_streak(active_days: set[date]) -> int:
    best = 0
    for day in active_days:
        if day - timedelta(days=1) in active_days:
            continue
        length = 0
        while day + timedelta(days=length) in active_days:
            length += 1
        best = max(best, length)
    return best
