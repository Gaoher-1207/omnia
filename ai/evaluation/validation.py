"""Reject malformed evaluation definitions before they can report a false pass."""

from collections.abc import Mapping

from Gaoher.ai.agent.validation import InvalidContext, InvalidModelOutput, validate_context_shape, validate_route
from Gaoher.ai.memory.models import MemorySelectionRequest
from .models import EvaluationScenario


class InvalidScenario(ValueError):
    pass


SCENARIO_CATEGORIES = frozenset({
    "general", "study_planning", "productivity_planning", "recommendation", "progress", "goals", "streaks",
    "nutrition", "coaching", "continuity", "action", "ambiguous", "insufficient_context", "empty_context",
    "user_isolation", "sensitive_information", "invalid_model_output", "provider_failure", "context_policy_violation", "memory_misuse",
})
_STATUSES = {"ready", "proposal", "proposed", "error", "clarification", "estimated", "insufficient_context", "unclear", "conflict"}
_MODULES = {"general", "planning", "recommendation", "progress", "goals_streaks", "nutrition", "coaching", "action"}


def validate_scenario(scenario: EvaluationScenario) -> EvaluationScenario:
    if not isinstance(scenario, EvaluationScenario):
        raise InvalidScenario("scenario must use the EvaluationScenario contract")
    if not isinstance(scenario.scenario_id, str) or not scenario.scenario_id.strip() or len(scenario.scenario_id) > 100:
        raise InvalidScenario("scenario ID is invalid")
    if scenario.category not in SCENARIO_CATEGORIES:
        raise InvalidScenario("scenario category is unsupported")
    if not isinstance(scenario.user_id, str) or not scenario.user_id.strip() or len(scenario.user_id) > 256:
        raise InvalidScenario("scenario user scope is invalid")
    if not isinstance(scenario.user_request, str) or not scenario.user_request.strip() or len(scenario.user_request) > 4000:
        raise InvalidScenario("scenario request is empty or too large")
    if not isinstance(scenario.authorized_context, Mapping):
        raise InvalidScenario("authorized context must be an object")
    try:
        validate_context_shape(scenario.authorized_context)
        route = validate_route(dict(scenario.expected_route))
    except (InvalidContext, InvalidModelOutput, TypeError, ValueError):
        raise InvalidScenario("scenario context or expected route is invalid") from None
    if scenario.expected_context_policy != (None if route["category"] == "general" else route["policy"]):
        raise InvalidScenario("expected context policy does not match route")
    if not isinstance(scenario.expected_memory_usage, bool) or route["use_memory"] != scenario.expected_memory_usage:
        raise InvalidScenario("expected memory behavior does not match route")
    if scenario.expected_result_status not in _STATUSES or scenario.expected_module not in _MODULES:
        raise InvalidScenario("expected result status or module is unsupported")
    module_for_intent = {"general": "general", "clarification": "general", "planning": "planning",
                         "recommendation": "recommendation", "progress": "progress", "goals_streaks": "goals_streaks",
                         "nutrition": "nutrition", "coaching": "coaching", "action": "action", "assistant": "general"}
    if scenario.expected_module != module_for_intent[route["intent"]]:
        raise InvalidScenario("expected module does not match route intent")
    if not isinstance(scenario.forbidden_behavior, tuple) or any(v not in {"direct_action_execution", "user_identity_in_payload", "unrelated_memory", "unrelated_context"} for v in scenario.forbidden_behavior):
        raise InvalidScenario("scenario contains unsupported forbidden behavior")
    if scenario.memory is not None:
        if not isinstance(scenario.memory, MemorySelectionRequest) or scenario.memory.user_id != scenario.user_id or scenario.memory.query.strip() != scenario.user_request.strip():
            raise InvalidScenario("scenario memory is not scoped to its request")
    if scenario.model_behavior not in {"normal", "provider_timeout", "provider_error", "empty_result", "malformed_result", "invalid_route", "oversized_result"}:
        raise InvalidScenario("scenario model behavior is unsupported")
    if not isinstance(scenario.notes, str) or len(scenario.notes) > 500:
        raise InvalidScenario("scenario notes are invalid")
    return scenario
