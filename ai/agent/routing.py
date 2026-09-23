"""Semantic request routing using structured model output."""

from typing import Any, Mapping

from .model_adapter import ModelAdapter, ModelCallOptions, call_structured
from .validation import validate_route


class RequestRouter:
    def __init__(self, model: ModelAdapter):
        self._model = model

    def route(self, message: str, *, options: ModelCallOptions | None = None) -> Mapping[str, Any]:
        raw = call_structured(self._model, "route_request", {"message": message}, options=options)
        return validate_route(raw)
