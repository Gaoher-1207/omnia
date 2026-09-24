"""Coaching over request-scoped selected context; no retrieval or action execution."""

from Gaoher.ai.agent.model_adapter import ModelCallOptions, call_structured
from Gaoher.ai.agent.models import thaw_json
from Gaoher.ai.agent.validation import validate_context_shape
from .models import CoachingRequest, CoachingRequestType
from .validation import validate_coaching_output


class CoachingService:
    def __init__(self, model_adapter, *, options: ModelCallOptions | None = None):
        self._adapter, self._options = model_adapter, options

    def coach(self, request: CoachingRequest):
        if not isinstance(request, CoachingRequest):
            raise TypeError("request must be a CoachingRequest")
        if request.request_type is CoachingRequestType.GENERAL:
            return None  # Keep ordinary knowledge questions on the normal agent path.
        selected = thaw_json(request.selected_context.for_user(request.user_id))
        validate_context_shape(selected)
        history = [dict(entry) for entry in request.conversation_context]
        validate_context_shape({"conversation": history})
        raw = call_structured(self._adapter, "coach", {
            "request": request.text.strip(),
            "request_type": request.request_type.value,
            "authorized_selected_context": selected,
            "conversation_context": history,
        }, options=self._options)
        return validate_coaching_output(raw, context=selected)
