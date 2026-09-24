"""Recommendation request and structured result contracts."""

from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping

from Gaoher.ai.context.context_manager import SelectedContext


class RecommendationStatus(str, Enum):
    READY = "ready"
    INSUFFICIENT_CONTEXT = "insufficient_context"
    CLARIFICATION = "clarification"


class RecommendationPriority(str, Enum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class RecommendationType(str, Enum):
    STUDY = "study"
    TASK = "task"
    PROGRESS = "progress"
    GOAL = "goal"
    FITNESS = "fitness"
    NUTRITION = "nutrition"
    ROUTINE = "routine"
    FOCUS = "focus"


@dataclass(frozen=True)
class RecommendationRequest:
    user_id: str
    text: str
    selected_context: SelectedContext | Mapping[str, Any]
    is_recommendation_request: bool = True
    is_recommendation_request: bool = True

    def __post_init__(self):
        if not isinstance(self.user_id, str) or not self.user_id.strip() or len(self.user_id) > 256:
            raise ValueError("user_id must be a non-empty request identity")
        if not isinstance(self.text, str) or not self.text.strip() or len(self.text) > 4000:
            raise ValueError("recommendation request must be non-empty text of at most 4000 characters")
        if not isinstance(self.selected_context, (SelectedContext, Mapping)):
            raise ValueError("selected_context must be Context Intelligence output")
        if not isinstance(self.is_recommendation_request, bool):
            raise ValueError("is_recommendation_request must be a boolean")
        if not isinstance(self.is_recommendation_request, bool):
            raise ValueError("is_recommendation_request must be a boolean")


@dataclass(frozen=True)
class Recommendation:
    type: RecommendationType
    recommendation: str
    reason: str
    priority: RecommendationPriority
    expected_benefit: str
    related_domain: str | None
    supporting_context: str | None


@dataclass(frozen=True)
class RecommendationResult:
    status: RecommendationStatus
    recommendations: tuple[Recommendation, ...]
    confidence: str
    uncertainty: str | None
    clarification_question: str | None
