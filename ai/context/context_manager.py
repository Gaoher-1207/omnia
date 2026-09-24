"""Backend-controlled category-to-domain context policies."""

import json
from dataclasses import dataclass
from enum import Enum
from types import MappingProxyType
from typing import Any, Mapping

from ..agent.models import freeze_json
from ..agent.validation import InvalidContext, ROUTE_POLICY_ALLOWLIST, validate_context_shape


# Domain names are application-owned identifiers, never model-selected fields.
class ContextDomain(str, Enum):
    TASKS = "tasks"
    SCHEDULE = "schedule"
    EXAMS = "exams"
    STUDY_PROGRESS = "study_progress"
    PREFERENCES = "preferences"
    RECENT_PLAN = "recent_plan"
    ACTIVITY = "activity"
    FITNESS = "fitness"
    NUTRITION = "nutrition"
    SLEEP = "sleep"
    GOALS = "goals"
    STREAKS = "streaks"
    TIME_CONTEXT = "time_context"
    RECENT_FEEDBACK = "recent_feedback"


# Policy mappings are application-controlled and intentionally narrow.
CONTEXT_POLICIES = MappingProxyType({
    "general": frozenset(),
    "study": frozenset({"exams", "study_progress", "tasks", "preferences"}),
    "productivity": frozenset({"tasks", "goals", "preferences", "recent_plan"}),
    "task_action": frozenset({"tasks", "schedule", "preferences"}),
    "fitness": frozenset({"activity", "fitness", "preferences"}),
    "food": frozenset({"nutrition", "preferences"}),
    "sleep": frozenset({"sleep", "preferences"}),
    "goals": frozenset({"goals", "streaks", "time_context", "recent_feedback", "preferences"}),
    "progress": frozenset({"study_progress", "tasks", "activity", "fitness", "sleep", "nutrition", "goals", "streaks"}),
    "other": frozenset(),
})

TASK_CONTEXT_POLICIES = MappingProxyType({
    "general": frozenset(),
    "study_planning": CONTEXT_POLICIES["study"],
    "nutrition": CONTEXT_POLICIES["food"],
    "progress_review": CONTEXT_POLICIES["progress"],
    "task_action": CONTEXT_POLICIES["task_action"],
})


@dataclass(frozen=True)
class AuthorizedContext:
    """Backend-provided context tagged to the authenticated request owner."""
    user_id: str
    values: Mapping[str, Any]

    def __post_init__(self):
        if not isinstance(self.user_id, str) or not self.user_id.strip() or len(self.user_id) > 256:
            raise InvalidContext("authorized context owner is invalid")
        if not isinstance(self.values, Mapping):
            raise InvalidContext("authorized context must be a mapping")


@dataclass(frozen=True)
class SelectedContext:
    """Request-scoped immutable context; identity is not part of model_payload."""
    user_id: str
    data: Mapping[str, Any]

    def for_user(self, user_id: str) -> Mapping[str, Any]:
        if user_id != self.user_id:
            raise InvalidContext("context does not belong to this request user")
        return self.data


class ContextManager:
    """Selects and freezes only the fields permitted by a validated policy."""

    def select(self, available: Mapping[str, Any], *, category: str, policy: str) -> Mapping[str, Any]:
        if category not in ROUTE_POLICY_ALLOWLIST or policy not in ROUTE_POLICY_ALLOWLIST[category]:
            raise InvalidContext("context policy is not permitted for request category")
        if not isinstance(available, Mapping):
            raise InvalidContext("context provider must return a mapping")
        allowed = CONTEXT_POLICIES[policy]
        selected = {key: available[key] for key in sorted(allowed) if key in available and available[key] is not None}
        validate_context_shape(selected)
        try:
            snapshot = json.loads(json.dumps(selected, ensure_ascii=False, separators=(",", ":"), allow_nan=False))
        except (TypeError, ValueError, RecursionError) as exc:
            raise InvalidContext("context is not safe JSON") from exc
        return freeze_json(snapshot)

    def select_task(
        self, available: Mapping[str, Any], *, task: str, requested_domains=None,
    ) -> Mapping[str, Any]:
        """Select domains by fixed task policy; caller/model cannot expand policy."""
        if not isinstance(task, str) or task not in TASK_CONTEXT_POLICIES:
            raise InvalidContext("unknown context task")
        allowed = TASK_CONTEXT_POLICIES[task]
        if requested_domains is not None:
            if isinstance(requested_domains, (str, bytes)):
                raise InvalidContext("requested domains must be a collection")
            try:
                requested = set(requested_domains)
            except TypeError:
                raise InvalidContext("requested domains must be a collection") from None
            if not requested.issubset(allowed):
                raise InvalidContext("requested context domain is not permitted for task")
        return self._select_allowed(available, allowed)

    def select_for_user(
        self, authorized: AuthorizedContext, *, user_id: str, category: str, policy: str,
    ) -> SelectedContext:
        if not isinstance(authorized, AuthorizedContext) or authorized.user_id != user_id:
            raise InvalidContext("authorized context does not belong to this request user")
        return SelectedContext(user_id, self.select(authorized.values, category=category, policy=policy))

    def _select_allowed(self, available: Mapping[str, Any], allowed) -> Mapping[str, Any]:
        if not isinstance(available, Mapping):
            raise InvalidContext("context provider must return a mapping")
        selected = {key: available[key] for key in sorted(allowed) if key in available and available[key] is not None}
        validate_context_shape(selected)
        try:
            snapshot = json.loads(json.dumps(selected, ensure_ascii=False, separators=(",", ":"), allow_nan=False))
        except (TypeError, ValueError, RecursionError) as exc:
            raise InvalidContext("context is not safe JSON") from exc
        return freeze_json(snapshot)
