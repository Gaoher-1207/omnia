"""Coaching request, response, insight, and suggested-action contracts."""

from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping

from Gaoher.ai.context.context_manager import SelectedContext


class CoachingStatus(str, Enum):
    READY = "ready"
    CLARIFICATION = "clarification"
    INSUFFICIENT_CONTEXT = "insufficient_context"


class CoachingTone(str, Enum):
    SUPPORTIVE = "supportive"
    PRACTICAL = "practical"
    NEUTRAL = "neutral"


class CoachingRequestType(str, Enum):
    COACHING = "coaching"
    GENERAL = "general"
    ACTION = "action"


@dataclass(frozen=True)
class CoachingQuestion:
    question: str


@dataclass(frozen=True)
class CoachingInsight:
    text: str
    supporting_reference: str | None


@dataclass(frozen=True)
class CoachingAction:
    suggestion: str
    reason: str
    related_domain: str | None


@dataclass(frozen=True)
class CoachingRequest:
    user_id: str
    text: str
    selected_context: SelectedContext
    request_type: CoachingRequestType = CoachingRequestType.COACHING
    conversation_context: tuple[Mapping[str, Any], ...] = ()

    def __post_init__(self):
        if not isinstance(self.user_id, str) or not self.user_id.strip() or len(self.user_id) > 256:
            raise ValueError("user_id must be a non-empty request identity")
        if not isinstance(self.text, str) or not self.text.strip() or len(self.text) > 4000:
            raise ValueError("coaching request must be non-empty text of at most 4000 characters")
        if not isinstance(self.selected_context, SelectedContext):
            raise ValueError("selected_context must come from Context Intelligence")
        if not isinstance(self.request_type, CoachingRequestType):
            raise ValueError("request_type must be a CoachingRequestType")
        if not isinstance(self.conversation_context, (tuple, list)) or len(self.conversation_context) > 8:
            raise ValueError("conversation context must contain at most 8 entries")
        if any(not isinstance(entry, Mapping) for entry in self.conversation_context):
            raise ValueError("conversation context entries must be objects")
        if any(not isinstance(entry, Mapping) for entry in self.conversation_context):
            raise ValueError("conversation context entries must be objects")


@dataclass(frozen=True)
class CoachingResult:
    status: CoachingStatus
    response: str
    tone: CoachingTone
    domain: str | None
    key_insight: CoachingInsight | None
    suggested_next_steps: tuple[CoachingAction, ...]
    questions: tuple[CoachingQuestion, ...]
    confidence: str
    uncertainty: str | None
