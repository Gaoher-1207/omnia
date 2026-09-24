"""Text-only nutrition analysis using the provider-neutral ModelAdapter."""

from Gaoher.ai.agent.model_adapter import ModelCallOptions, call_structured
from Gaoher.ai.food.calorie_estimation import NutritionRequest, validate_nutrition_output


class NutritionAnalysisService:
    def __init__(self, model_adapter, *, options: ModelCallOptions | None = None):
        self._adapter, self._options = model_adapter, options

    def analyze(self, request: NutritionRequest):
        if not isinstance(request, NutritionRequest):
            raise TypeError("request must be a NutritionRequest")
        raw = call_structured(self._adapter, "analyze_nutrition", {"food_description": request.text.strip()}, options=self._options)
        return validate_nutrition_output(raw)
