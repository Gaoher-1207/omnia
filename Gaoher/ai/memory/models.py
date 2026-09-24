"""Memory contracts with explicit ownership, type, and lifetime boundaries."""

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any


class MemoryType(str, Enum):
    CONVERSATION = "conversation"
    SUMMARY = "summary"
    PREFERENCE = "preference"
    SESSION_CONTEXT = "session_context"


class MemoryLifetime(str, Enum):
    REQUEST = "request_scoped"
    SESSION = "session_scoped"
    PERSISTENT_CANDIDATE = "persistent_candidate"


class Sensitivity(str, Enum):
    NON_SENSITIVE = "non_sensitive"
    PERSONAL = "personal"
    SENSITIVE = "sensitive"


@dataclass(frozen=True)
class ConversationMessage:
    user_id: str
    role: str
    content: str
    timestamp: datetime | None = None


@dataclass(frozen=True)
class ConversationSummary:
    user_id: str
    content: str
    lifetime: MemoryLifetime = MemoryLifetime.SESSION


@dataclass(frozen=True)
class MemoryItem:
    user_id: str
    content: str
    memory_type: MemoryType
    lifetime: MemoryLifetime
    confidence: float
    relevance: float = 0.0
    explicitly_provided: bool = False


@dataclass(frozen=True)
class MemoryCandidate:
    user_id: str
    content: str
    memory_type: MemoryType
    reason: str
    confidence: float
    suggested_lifetime: MemoryLifetime
    sensitivity: Sensitivity


@dataclass(frozen=True)
class MemorySelectionRequest:
    user_id: str
    query: str
    messages: tuple[ConversationMessage, ...] = ()
    summary: ConversationSummary | None = None
    memories: tuple[MemoryItem, ...] = ()
    is_general: bool = False


@dataclass(frozen=True)
class MemorySelectionResult:
    user_id: str
    messages: tuple[ConversationMessage, ...]
    summary: ConversationSummary | None
    memories: tuple[MemoryItem, ...]
    is_general: bool

    def for_model(self, user_id: str) -> dict[str, Any]:
        if user_id != self.user_id:
            raise ValueError("memory selection belongs to another user")
        return {
            "messages": [{"role": m.role, "content": m.content, "timestamp": m.timestamp.isoformat() if m.timestamp else None} for m in self.messages],
            "summary": self.summary.content if self.summary else None,
            "memories": [{"content": m.content, "type": m.memory_type.value, "lifetime": m.lifetime.value} for m in self.memories],
        }
