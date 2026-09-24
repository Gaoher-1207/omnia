"""Immutable inputs and outputs for proposed plans."""

from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping


class PlanStatus(str, Enum):
    PROPOSED = "proposed"
    CLARIFICATION = "clarification"
    CONFLICT = "conflict"


@dataclass(frozen=True)
class PlanningRequest:
    text: str
    context: Mapping[str, Any]
    adaptation: bool = False

    def __post_init__(self):
        if not isinstance(self.text, str) or not self.text.strip() or len(self.text) > 4000:
            raise ValueError("planning request must be non-empty text of at most 4000 characters")
        if not isinstance(self.context, Mapping):
            raise ValueError("authorized context must be an object")
        if not isinstance(self.adaptation, bool):
            raise ValueError("adaptation must be a boolean")


@dataclass(frozen=True)
class PlanSession:
    title: str
    day: str | None
    duration_minutes: int
    break_after_minutes: int | None
    priority: str
    reason: str


@dataclass(frozen=True)
class PlanningResult:
    status: PlanStatus
    sessions: tuple[PlanSession, ...]
    assumptions: tuple[str, ...]
    uncertainties: tuple[str, ...]
    clarification_question: str | None
