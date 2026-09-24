"""Provider-neutral goal/streak analysis using only Context Intelligence output."""

from Gaoher.ai.agent.model_adapter import ModelCallOptions, call_structured
from Gaoher.ai.agent.models import thaw_json
from Gaoher.ai.agent.validation import validate_context_shape
from .models import GoalsStreaksRequest
from .validation import validate_goals_streaks_output


class GoalsStreaksService:
    def __init__(self, model_adapter, *, options: ModelCallOptions | None = None):
        self._adapter, self._options = model_adapter, options

    def analyze(self, request: GoalsStreaksRequest):
        if not isinstance(request, GoalsStreaksRequest):
            raise TypeError("request must be a GoalsStreaksRequest")
        context = thaw_json(request.selected_context.for_user(request.user_id))
        validate_context_shape(context)
        raw = call_structured(self._adapter, "analyze_goals_streaks", {
            "request": request.text.strip(), "authorized_selected_context": context,
        }, options=self._options)
        return validate_goals_streaks_output(raw, context=context)
