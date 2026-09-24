"""Immutable action registry and backend executor contract."""

from dataclasses import dataclass
from types import MappingProxyType
from typing import Mapping, Protocol

from .models import ConfirmedAction, ExecutorResult, ExecutorStatus


@dataclass(frozen=True)
class ActionDefinition:
    name: str
    required_arguments: Mapping[str, type]
    optional_arguments: Mapping[str, type]
    allowed_context_policy: str
    requires_confirmation: bool = True


ACTION_REGISTRY: Mapping[str, ActionDefinition] = MappingProxyType({
    "create_task": ActionDefinition(
        "create_task", MappingProxyType({"title": str}), MappingProxyType({"due_at": str}), "task_action"
    ),
    "reschedule_task": ActionDefinition(
        "reschedule_task", MappingProxyType({"task_id": str, "new_due_at": str}),
        MappingProxyType({}), "task_action"
    ),
})


class ActionExecutor(Protocol):
    def execute(self, *, action: ConfirmedAction) -> ExecutorResult:
        """Recheck auth, ownership, permission, state, receipt, expiry, and idempotency.

        The confirmation receipt and idempotency key come from the trusted
        proposal store. Model output and client arguments are never authority.
        """


class PendingActionExecutor:
    def execute(self, *, action: ConfirmedAction) -> ExecutorResult:
        return ExecutorResult(ExecutorStatus.NOT_CONNECTED)
