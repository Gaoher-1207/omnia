"""Structured contracts for progress facts, metrics, and interpretation."""

from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping

from Gaoher.ai.context.context_manager import SelectedContext


class ProgressStatus(str, Enum):
    READY = "ready"
    INSUFFICIENT_CONTEXT = "insufficient_context"
    CLARIFICATION = "clarification"


class ProgressTrend(str, Enum):
    IMPROVING = "improving"
    STABLE = "stable"
    DECLINING = "declining"
    INSUFFICIENT_DATA = "insufficient_data"


@dataclass(frozen=True)
class ProgressRequest:
    user_id: str
    text: str
    selected_context: SelectedContext

    def __post_init__(self):
        if not isinstance(self.user_id, str) or not self.user_id.strip() or len(self.user_id) > 256:
            raise ValueError("user_id must be a non-empty request identity")
        if not isinstance(self.text, str) or not self.text.strip() or len(self.text) > 4000:
            raise ValueError("progress request must be non-empty text of at most 4000 characters")
        if not isinstance(self.selected_context, SelectedContext):
            raise ValueError("selected_context must come from Context Intelligence")


@dataclass(frozen=True)
class ProgressMetric:
    name: str
    completed: float | None
    total: float | None
    completion_rate: float | None


@dataclass(frozen=True)
class ProgressArea:
    domain: str
    summary: str
    metrics: tuple[ProgressMetric, ...]
    trend: ProgressTrend


@dataclass(frozen=True)
class ProgressSummary:
    fact: str
    interpretation: str | None


@dataclass(frozen=True)
class ProgressResult:
    status: ProgressStatus
    summary: ProgressSummary | None
    completed_items: tuple[str, ...]
    metrics: tuple[ProgressMetric, ...]
    areas: tuple[ProgressArea, ...]
    strengths: tuple[str, ...]
    attention_areas: tuple[str, ...]
    trends: tuple[ProgressTrend, ...]
    blockers: tuple[str, ...]
    suggested_next_focus: str | None
    confidence: str
    uncertainty: str | None
    clarification_question: str | None
