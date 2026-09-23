"""Provider-neutral bounded model-call contract; no provider is configured."""

import json
import time
from dataclasses import dataclass
from math import isfinite
from threading import Event
from typing import Any, Mapping, Protocol


MAX_MODEL_PAYLOAD_BYTES = 32_000
MAX_MODEL_OUTPUT_BYTES = 8_192
MAX_MODEL_TIMEOUT_SECONDS = 30.0


class ProviderFailure(RuntimeError):
    """Base class for provider-boundary failures; messages must not be surfaced."""


class ProviderTimeout(ProviderFailure):
    pass


class ProviderUnavailable(ProviderFailure):
    pass


class StructuredOutputFailure(ProviderFailure):
    pass


class ModelRequestCancelled(ProviderFailure):
    pass


class ModelPayloadTooLarge(ProviderFailure):
    pass


class ModelOutputTooLarge(ProviderFailure):
    pass


class ModelIntegrationPending(ProviderFailure):
    """Raised when no model provider has been configured."""


@dataclass(frozen=True)
class ModelCallOptions:
    timeout_seconds: float = 15.0
    max_output_bytes: int = MAX_MODEL_OUTPUT_BYTES
    cancellation: Event | None = None


class ModelAdapter(Protocol):
    def generate_structured(
        self, task: str, payload: Mapping[str, Any], *, options: ModelCallOptions
    ) -> Mapping[str, Any]:
        """Enforce timeout/cancellation and return a schema candidate.

        Implementations must use an actual provider-side/client timeout and
        check cancellation where supported; the coordinator also enforces
        payload/output byte limits and checks elapsed time after return.
        """


def call_structured(
    adapter: ModelAdapter,
    task: str,
    payload: Mapping[str, Any],
    *,
    options: ModelCallOptions | None = None,
) -> Mapping[str, Any]:
    options = options or ModelCallOptions()
    if (
        not isfinite(options.timeout_seconds)
        or options.timeout_seconds <= 0
        or options.timeout_seconds > MAX_MODEL_TIMEOUT_SECONDS
        or options.max_output_bytes <= 0
        or options.max_output_bytes > MAX_MODEL_OUTPUT_BYTES
    ):
        raise ValueError("model limits are outside the supported range")
    if options.cancellation is not None and options.cancellation.is_set():
        raise ModelRequestCancelled("request cancelled")
    try:
        _guard_structure(payload, MAX_MODEL_PAYLOAD_BYTES, MAX_MODEL_PAYLOAD_BYTES, ModelPayloadTooLarge)
        encoded_payload = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, RecursionError) as exc:
        raise StructuredOutputFailure("request payload is not JSON serializable") from exc
    if len(encoded_payload) > MAX_MODEL_PAYLOAD_BYTES:
        raise ModelPayloadTooLarge("model request payload exceeds limit")
    started = time.monotonic()
    result = adapter.generate_structured(task, payload, options=options)
    if time.monotonic() - started > options.timeout_seconds:
        raise ProviderTimeout("model call exceeded configured timeout")
    if options.cancellation is not None and options.cancellation.is_set():
        raise ModelRequestCancelled("request cancelled")
    try:
        _guard_structure(result, options.max_output_bytes, 2_000, ModelOutputTooLarge)
        encoded_output = json.dumps(result, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, RecursionError) as exc:
        raise StructuredOutputFailure("model output is not valid structured JSON") from exc
    if len(encoded_output) > options.max_output_bytes:
        raise ModelOutputTooLarge("model output exceeds limit")
    normalized = json.loads(encoded_output)
    if not isinstance(normalized, dict):
        raise StructuredOutputFailure("model output must be an object")
    return normalized


def _guard_structure(value: Any, max_string_length: int, max_items: int, error_type: type[Exception]) -> None:
    """Reject oversized JSON structures before building encoded copies."""
    counter = [0]

    def visit(item: Any, depth: int) -> None:
        counter[0] += 1
        if counter[0] > max_items or depth > 20:
            raise error_type("model JSON structure exceeds limits")
        if isinstance(item, str):
            if len(item) > max_string_length:
                raise error_type("model JSON string exceeds limit")
        elif isinstance(item, Mapping):
            for key, nested in item.items():
                visit(key, depth + 1)
                visit(nested, depth + 1)
        elif isinstance(item, (list, tuple)):
            for nested in item:
                visit(nested, depth + 1)

    visit(value, 0)


class PendingModelAdapter:
    """Safe default: makes no network calls and never fabricates a response."""

    def generate_structured(
        self, task: str, payload: Mapping[str, Any], *, options: ModelCallOptions
    ) -> Mapping[str, Any]:
        raise ModelIntegrationPending("Model integration is pending.")
