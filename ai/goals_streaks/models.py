"""Contracts for goal and streak analysis; values reflect supplied context only."""

from dataclasses import dataclass
from enum import Enum

from Gaoher.ai.context.context_manager import SelectedContext


class GoalStatus(str, Enum):
    ACTIVE = "active"
    COMPLETED = "completed"
    PAUSED = "paused"
    MISSED = "missed"
    CANCELLED = "cancelled"
    UNKNOWN = "unknown"


class StreakStatus(str, Enum):
    ACTIVE = "active"
    BROKEN = "broken"
    LONGEST = "longest"
    AT_RISK = "at_risk"
    INSUFFICIENT_DATA = "insufficient_data"


class GoalsStreaksStatus(str, Enum):
    READY = "ready"
    INSUFFICIENT_CONTEXT = "insufficient_context"
    CLARIFICATION = "clarification"


class DeadlineAssessment(str, Enum):
    APPROACHING = "approaching"
    OVERDUE = "overdue"
    SUFFICIENT_TIME = "sufficient_time"
    INSUFFICIENT_INFORMATION = "insufficient_information"


@dataclass(frozen=True)
class GoalProgress:
    current_value: float | None
    target: float | None
    progress: float | None


@dataclass(frozen=True)
class Goal:
    reference: str | None
    title: str
    domain: str | None
    status: GoalStatus
    progress: GoalProgress
    deadline: str | None
    priority: str | None
    deadline_assessment: DeadlineAssessment


@dataclass(frozen=True)
class Streak:
    domain: str
    streak_type: str
    current_streak: int | None
    longest_streak: int | None
    status: StreakStatus
    last_activity: str | None


@dataclass(frozen=True)
class GoalInsight:
    text: str
    related_goal: str | None
    kind: str


@dataclass(frozen=True)
class GoalConflict:
    goal_references: tuple[str, ...]
    shared_constraint: str
    explanation: str


@dataclass(frozen=True)
class GoalsStreaksRequest:
    user_id: str
    text: str
    selected_context: SelectedContext

    def __post_init__(self):
        if not isinstance(self.user_id, str) or not self.user_id.strip() or len(self.user_id) > 256:
            raise ValueError("user_id must be a non-empty request identity")
        if not isinstance(self.text, str) or not self.text.strip() or len(self.text) > 4000:
            raise ValueError("request text must be non-empty and bounded")
        if not isinstance(self.selected_context, SelectedContext):
            raise ValueError("selected_context must come from Context Intelligence")


@dataclass(frozen=True)
class GoalsStreaksResult:
    status: GoalsStreaksStatus
    goal_summary: str | None
    goals: tuple[Goal, ...]
    active_goals: tuple[str, ...]
    completed_goals: tuple[str, ...]
    goals_needing_attention: tuple[str, ...]
    streak_summary: str | None
    streaks: tuple[Streak, ...]
    streak_insights: tuple[str, ...]
    goal_insights: tuple[GoalInsight, ...]
    goal_conflicts: tuple[GoalConflict, ...]
    suggested_next_focus: str | None
    confidence: str
    uncertainty: str | None
    clarification_question: str | None
