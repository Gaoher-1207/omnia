"""Immutable request, context, confirmation, and response contracts."""

from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from types import MappingProxyType
from typing import Any, Mapping


def freeze_json(value: Any) -> Any:
    """Copy JSON-like values into recursively immutable equivalents."""
    if isinstance(value, Mapping):
        return MappingProxyType({str(k): freeze_json(v) for k, v in value.items()})
    if isinstance(value, (list, tuple)):
        return tuple(freeze_json(item) for item in value)
    return value


def thaw_json(value: Any) -> Any:
    """Return fresh JSON-compatible containers for adapters and integrations."""
    if isinstance(value, Mapping):
        return {str(k): thaw_json(v) for k, v in value.items()}
    if isinstance(value, tuple):
        return [thaw_json(item) for item in value]
    return value


@dataclass(frozen=True)
class AgentRequest:
    """A single authenticated request; user_id must come from Django auth."""

    user_id: str
    message: str
    proposal_id: str | None = None
    confirmation_token: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.user_id, str) or not self.user_id.strip():
            raise ValueError("user_id must be a non-empty authenticated identity")
        if len(self.user_id) > 256:
            raise ValueError("user_id exceeds the supported length")
        if not isinstance(self.message, str) or not self.message.strip():
            raise ValueError("message must be a non-empty string")
        if (self.proposal_id is None) != (self.confirmation_token is None):
            raise ValueError("proposal_id and confirmation_token must be supplied together")
        if self.proposal_id is not None and (
            not isinstance(self.proposal_id, str) or not self.proposal_id or len(self.proposal_id) > 128
        ):
            raise ValueError("proposal_id is invalid")
        if self.confirmation_token is not None and (
            not isinstance(self.confirmation_token, str)
            or not self.confirmation_token
            or len(self.confirmation_token) > 4096
        ):
            raise ValueError("confirmation_token is invalid")


@dataclass(frozen=True)
class ActionProposal:
    name: str
    arguments: Mapping[str, Any]
    proposal_id: str
    expires_at: datetime
    requires_confirmation: bool = True

    def __post_init__(self) -> None:
        if not isinstance(self.expires_at, datetime):
            raise ValueError("proposal expiry must be a datetime")
        if self.expires_at.tzinfo is None or self.expires_at.utcoffset() is None:
            raise ValueError("proposal expiry must be timezone-aware")
        if not isinstance(self.proposal_id, str) or not self.proposal_id:
            raise ValueError("proposal_id must be non-empty")
        object.__setattr__(self, "arguments", freeze_json(self.arguments))


@dataclass(frozen=True)
class ConfirmedAction:
    """Authoritative proposal claim returned by a trusted backend proposal store."""

    user_id: str
    proposal: ActionProposal
    confirmation_receipt: str
    idempotency_key: str

    def __post_init__(self) -> None:
        if not isinstance(self.user_id, str) or not self.user_id:
            raise ValueError("confirmed action must have a user identity")
        if not isinstance(self.proposal, ActionProposal):
            raise ValueError("confirmed action must contain a stored proposal")
        if not isinstance(self.confirmation_receipt, str) or not self.confirmation_receipt:
            raise ValueError("confirmed action must have a backend receipt")
        if not isinstance(self.idempotency_key, str) or not self.idempotency_key:
            raise ValueError("confirmed action must have an idempotency key")


class ExecutorStatus(str, Enum):
    SUCCESS = "success"
    DENIED = "denied"
    FAILED = "failed"
    NOT_CONNECTED = "not_connected"
    AMBIGUOUS = "ambiguous"


@dataclass(frozen=True)
class ExecutorResult:
    status: ExecutorStatus
    result_reference: str | None = None
    error_category: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.status, ExecutorStatus):
            raise ValueError("executor result must use a known status")


class ErrorCategory(str, Enum):
    MODEL_PENDING = "model_pending"
    PROVIDER_TIMEOUT = "provider_timeout"
    PROVIDER_UNAVAILABLE = "provider_unavailable"
    PROVIDER_FAILURE = "provider_failure"
    INVALID_MODEL_OUTPUT = "invalid_model_output"
    MODEL_CANCELLED = "model_cancelled"
    CONTEXT_UNAVAILABLE = "context_unavailable"
    INVALID_CONTEXT = "invalid_context"
    CONFIRMATION_REJECTED = "confirmation_rejected"
    ACTION_DENIED = "action_denied"
    ACTION_FAILED = "action_failed"
    ACTION_AMBIGUOUS = "action_ambiguous"
    ACTION_NOT_CONNECTED = "action_not_connected"
    INTERNAL_FAILURE = "internal_failure"


@dataclass(frozen=True)
class AgentError:
    category: ErrorCategory
    correlation_id: str


@dataclass(frozen=True)
class AgentResponse:
    message: str
    kind: str = "answer"
    needs_clarification: bool = False
    action: ActionProposal | None = None
    needs_confirmation: bool = False
    action_status: ExecutorStatus | str | None = None
    error: AgentError | None = None
