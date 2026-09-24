"""Context-aware recommendation proposals through the provider-neutral adapter."""

from collections.abc import Mapping

from Gaoher.ai.agent.model_adapter import ModelCallOptions, call_structured
from Gaoher.ai.agent.models import thaw_json
from Gaoher.ai.agent.validation import validate_context_shape
from Gaoher.ai.context.context_manager import SelectedContext
from .models import RecommendationRequest
from .validation import validate_recommendation_output


class RecommendationService:
    def __init__(self, model_adapter, *, options: ModelCallOptions | None = None):
        self._adapter, self._options = model_adapter, options

    def recommend(self, request: RecommendationRequest):
        if not isinstance(request, RecommendationRequest):
            raise TypeError("request must be a RecommendationRequest")
        # The application router keeps ordinary knowledge questions on the
        # normal assistant path; they do not need personal context or a model call.
        if not request.is_recommendation_request:
            return None
        if isinstance(request.selected_context, SelectedContext):
            context = request.selected_context.for_user(request.user_id)
        else:
            context = request.selected_context
        if not isinstance(context, Mapping):
            raise ValueError("selected context must be a mapping")
        validate_context_shape(thaw_json(context))
        raw = call_structured(self._adapter, "recommend", {
            "request": request.text.strip(), "authorized_selected_context": thaw_json(context),
        }, options=self._options)
        return validate_recommendation_output(raw)
