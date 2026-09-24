"""Proposal-only planning service using the provider-neutral ModelAdapter."""

from Gaoher.ai.agent.model_adapter import ModelCallOptions, call_structured
from Gaoher.ai.agent.validation import validate_context_shape
from .models import PlanningRequest
from .validation import validate_planning_output


class PlanningService:
    def __init__(self, model_adapter, *, options: ModelCallOptions | None = None):
        self._adapter, self._options = model_adapter, options

    def create_plan(self, request: PlanningRequest):
        if not isinstance(request, PlanningRequest):
            raise TypeError("request must be a PlanningRequest")
        validate_context_shape(request.context)
        raw = call_structured(self._adapter, "create_plan", {
            "request": request.text.strip(), "authorized_context": dict(request.context), "adaptation": request.adaptation,
        }, options=self._options)
        return validate_planning_output(raw)
