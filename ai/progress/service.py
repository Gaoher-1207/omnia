"""Progress analysis over Context Intelligence output using ModelAdapter."""

from Gaoher.ai.agent.model_adapter import ModelCallOptions, call_structured
from Gaoher.ai.agent.models import thaw_json
from Gaoher.ai.agent.validation import validate_context_shape
from .models import ProgressRequest
from .validation import validate_progress_output


class ProgressService:
    def __init__(self, model_adapter, *, options: ModelCallOptions | None = None):
        self._adapter, self._options = model_adapter, options

    def analyze(self, request: ProgressRequest):
        if not isinstance(request, ProgressRequest):
            raise TypeError("request must be a ProgressRequest")
        selected = request.selected_context.for_user(request.user_id)
        context = thaw_json(selected)
        validate_context_shape(context)
        raw = call_structured(self._adapter, "analyze_progress", {
            "request": request.text.strip(), "authorized_selected_context": context,
        }, options=self._options)
        return validate_progress_output(raw, context=context)
