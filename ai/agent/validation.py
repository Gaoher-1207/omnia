"""Strict validation for untrusted model and backend context structures."""

import json
from datetime import datetime
from types import MappingProxyType
from typing import Any, Mapping

from .actions import ACTION_REGISTRY


class InvalidModelOutput(ValueError):
    pass


class InvalidContext(ValueError):
    pass


ROUTE_POLICY_ALLOWLIST = MappingProxyType({
    "general": frozenset({"general"}),
    "omnia": frozenset({"study", "productivity", "fitness", "food", "sleep", "goals", "progress", "other"}),
    "action": frozenset({"task_action"}),
})
MAX_CONTEXT_BYTES = 24_000
MAX_CONTEXT_FIELD_BYTES = 8_000
MAX_CONTEXT_DEPTH = 5
MAX_CONTEXT_ITEMS = 200
FORBIDDEN_KEY_PARTS = (
    "password", "secret", "token", "credential", "apikey", "authorization",
    "internalprompt", "systemprompt", "database", "infrastructure", "userid",
    "email", "phone", "address", "dateofbirth", "ssn",
)
ARGUMENT_MAX_LENGTH = {"title": 300, "task_id": 128, "due_at": 64, "new_due_at": 64}


def _object(value: Any, expected: set[str], label: str, error_type=InvalidModelOutput) -> Mapping[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise error_type(f"{label} has an invalid structure")
    return value


def validate_route(value: Any) -> Mapping[str, str]:
    route = _object(value, {"category", "policy"}, "route")
    category, policy = route["category"], route["policy"]
    if not isinstance(category, str) or category not in ROUTE_POLICY_ALLOWLIST:
        raise InvalidModelOutput("unsupported route category")
    if not isinstance(policy, str) or policy not in ROUTE_POLICY_ALLOWLIST[category]:
        raise InvalidModelOutput("route policy is not permitted for category")
    return {"category": category, "policy": policy}


def validate_assistant_result(
    value: Any, *, allowed_action_names: frozenset[str] = frozenset()
) -> Mapping[str, Any]:
    result = _object(value, {"kind", "message", "action"}, "assistant result")
    if not isinstance(result["kind"], str) or result["kind"] not in {"answer", "clarification", "action"}:
        raise InvalidModelOutput("unsupported assistant result kind")
    if not isinstance(result["message"], str) or not result["message"].strip() or len(result["message"]) > 8_000:
        raise InvalidModelOutput("message has invalid content or size")
    action = result["action"]
    if result["kind"] == "action":
        if not allowed_action_names:
            raise InvalidModelOutput("route does not permit actions")
        if not isinstance(action, dict) or set(action) != {"name", "arguments"}:
            raise InvalidModelOutput("action result has an invalid structure")
        name, args = action["name"], action["arguments"]
        if (
            not isinstance(name, str)
            or name not in ACTION_REGISTRY
            or name not in allowed_action_names
            or not isinstance(args, dict)
        ):
            raise InvalidModelOutput("action is not allowlisted or arguments are invalid")
        definition = ACTION_REGISTRY[name]
        required = set(definition.required_arguments)
        allowed = required | set(definition.optional_arguments)
        if not required.issubset(args) or not set(args).issubset(allowed):
            raise InvalidModelOutput("action arguments do not match the registered contract")
        for key, expected_type in {**definition.required_arguments, **definition.optional_arguments}.items():
            if key in args and (not isinstance(args[key], expected_type) or not args[key].strip()):
                raise InvalidModelOutput(f"action argument {key} has an invalid value")
            if key in args and len(args[key]) > ARGUMENT_MAX_LENGTH[key]:
                raise InvalidModelOutput(f"action argument {key} exceeds its limit")
            if key in args and key in {"due_at", "new_due_at"}:
                try:
                    timestamp = datetime.fromisoformat(args[key].replace("Z", "+00:00"))
                except ValueError as exc:
                    raise InvalidModelOutput(f"action argument {key} must be an ISO timestamp") from exc
                if timestamp.tzinfo is None or timestamp.utcoffset() is None:
                    raise InvalidModelOutput(f"action argument {key} must include a timezone")
    elif action is not None:
        raise InvalidModelOutput("only action results may contain an action")
    return result


def validate_context_shape(value: Any) -> None:
    """Check JSON safety, total/per-field bytes, depth, count, and sensitive keys."""
    if not isinstance(value, Mapping):
        raise InvalidContext("context must be an object")
    total_size = 2  # enclosing braces
    counter = [0]
    for key, item in value.items():
        if not isinstance(key, str) or len(key) > 128 or _forbidden_key(key):
            raise InvalidContext("context contains a forbidden key")
        _validate_nested(item, depth=1, counter=counter)
        field_size = _bounded_json_size({key: item}, MAX_CONTEXT_FIELD_BYTES)
        total_size += field_size + (1 if total_size > 2 else 0)
        if total_size > MAX_CONTEXT_BYTES:
            raise InvalidContext("context exceeds the request limit")


def _bounded_json_size(value: Any, limit: int) -> int:
    try:
        encoder = json.JSONEncoder(ensure_ascii=False, separators=(",", ":"), allow_nan=False)
        size = 0
        for chunk in encoder.iterencode(value):
            size += len(chunk.encode("utf-8"))
            if size > limit:
                raise InvalidContext("context exceeds the request limit")
        return size
    except InvalidContext:
        raise
    except (TypeError, ValueError, RecursionError) as exc:
        raise InvalidContext("context is not safe JSON") from exc


def _validate_nested(value: Any, *, depth: int, counter: list[int]) -> None:
    counter[0] += 1
    if counter[0] > MAX_CONTEXT_ITEMS or depth > MAX_CONTEXT_DEPTH:
        raise InvalidContext("context nesting or item count exceeds the request limit")
    if value is None or isinstance(value, (str, bool, int, float)):
        if isinstance(value, str) and len(value) > MAX_CONTEXT_BYTES:
            raise InvalidContext("context string exceeds the request limit")
        if isinstance(value, float) and (value != value or value in (float("inf"), float("-inf"))):
            raise InvalidContext("context contains a non-finite number")
        return
    if isinstance(value, list):
        for item in value:
            _validate_nested(item, depth=depth + 1, counter=counter)
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str) or len(key) > 128 or _forbidden_key(key):
                raise InvalidContext("context contains a forbidden nested key")
            _validate_nested(item, depth=depth + 1, counter=counter)
        return
    raise InvalidContext("context contains an unsupported value")


def _forbidden_key(key: str) -> bool:
    normalized = "".join(character for character in key.casefold() if character.isalnum())
    return any(part in normalized for part in FORBIDDEN_KEY_PARTS)
