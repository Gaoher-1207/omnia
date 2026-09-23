"""Backend-controlled category-to-domain context policies."""

import json
from types import MappingProxyType
from typing import Any, Mapping

from ..agent.models import freeze_json
from ..agent.validation import InvalidContext, ROUTE_POLICY_ALLOWLIST, validate_context_shape


# A policy represents one domain task, never an arbitrary field/database request.
CONTEXT_POLICIES = MappingProxyType({
    "general": frozenset(),
    "study": frozenset({"exams", "study_progress", "tasks", "preferences"}),
    "productivity": frozenset({"tasks", "goals", "preferences", "recent_plan"}),
    "task_action": frozenset({"tasks", "preferences"}),
    "fitness": frozenset({"activity", "fitness", "preferences"}),
    "food": frozenset({"nutrition", "preferences"}),
    "sleep": frozenset({"sleep", "preferences"}),
    "goals": frozenset({"goals", "recent_feedback", "preferences"}),
    "progress": frozenset({"study_progress", "activity", "fitness", "sleep", "nutrition", "goals"}),
    "other": frozenset(),
})


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
