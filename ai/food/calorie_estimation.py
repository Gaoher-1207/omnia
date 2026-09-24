"""Public nutrition contracts and validation for text based estimates."""

from dataclasses import dataclass
from enum import Enum
from math import isfinite


class NutritionStatus(str, Enum):
    ESTIMATED = "estimated"
    CLARIFICATION = "clarification"
    UNCLEAR = "unclear"


class Confidence(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


@dataclass(frozen=True)
class NutritionRequest:
    text: str

    def __post_init__(self):
        if not isinstance(self.text, str) or not self.text.strip():
            raise ValueError("food description must be non-empty text")
        if len(self.text) > 4000:
            raise ValueError("food description is too long")


@dataclass(frozen=True)
class FoodItemEstimate:
    name: str
    portion: str
    calories_kcal: float
    protein_g: float
    carbohydrates_g: float
    fat_g: float


@dataclass(frozen=True)
class NutritionResult:
    status: NutritionStatus
    items: tuple[FoodItemEstimate, ...]
    assumptions: tuple[str, ...]
    confidence: Confidence
    clarification_question: str | None = None
    estimated: bool = True

    @property
    def wording(self) -> str:
        return "Estimated nutrition (approximate; not an exact measurement)."

    @property
    def totals(self):
        if self.status is not NutritionStatus.ESTIMATED:
            return None
        return {key: round(sum(getattr(i, key) for i in self.items), 1) for key in
                ("calories_kcal", "protein_g", "carbohydrates_g", "fat_g")}


class InvalidNutritionOutput(ValueError):
    pass


_FIELDS = {"name", "portion", "calories_kcal", "protein_g", "carbohydrates_g", "fat_g"}
_LIMITS = {"calories_kcal": 10000, "protein_g": 500, "carbohydrates_g": 1000, "fat_g": 500}


def validate_nutrition_output(raw: dict) -> NutritionResult:
    if not isinstance(raw, dict) or set(raw) != {"status", "items", "assumptions", "confidence", "clarification_question"}:
        raise InvalidNutritionOutput("nutrition output has an invalid shape")
    try:
        status, confidence = NutritionStatus(raw["status"]), Confidence(raw["confidence"])
    except (ValueError, TypeError):
        raise InvalidNutritionOutput("unknown status or confidence") from None
    items_raw, assumptions, question = raw["items"], raw["assumptions"], raw["clarification_question"]
    if not isinstance(items_raw, list) or len(items_raw) > 50 or not isinstance(assumptions, list) or len(assumptions) > 50:
        raise InvalidNutritionOutput("invalid items or assumptions")
    if any(not isinstance(a, str) or not a.strip() or len(a) > 300 for a in assumptions):
        raise InvalidNutritionOutput("invalid assumption")
    if question is not None and (not isinstance(question, str) or len(question) > 500):
        raise InvalidNutritionOutput("invalid clarification question")
    if status is NutritionStatus.ESTIMATED:
        if not items_raw or question is not None:
            raise InvalidNutritionOutput("estimated result needs items and no question")
    elif not question or any(isinstance(i, dict) and any(i.get(k) is not None for k in _LIMITS) for i in items_raw):
        raise InvalidNutritionOutput("clarification and unclear results need a question and no nutrient estimates")
    items = []
    for item in items_raw:
        if not isinstance(item, dict) or set(item) != _FIELDS:
            raise InvalidNutritionOutput("food item has an invalid shape")
        name, portion = item["name"], item["portion"]
        if not isinstance(name, str) or not name.strip() or len(name) > 120 or not isinstance(portion, str) or not portion.strip() or len(portion) > 200:
            raise InvalidNutritionOutput("food name or portion is invalid")
        values = {}
        for key, maximum in _LIMITS.items():
            val = item[key]
            if isinstance(val, bool) or not isinstance(val, (int, float)) or not isfinite(val) or val < 0 or val > maximum:
                raise InvalidNutritionOutput("nutrient value is unrealistic or invalid")
            values[key] = float(val)
        energy = 4 * (values["protein_g"] + values["carbohydrates_g"]) + 9 * values["fat_g"]
        if values["calories_kcal"] and abs(energy - values["calories_kcal"]) > max(250, values["calories_kcal"] * .75):
            raise InvalidNutritionOutput("calories and macronutrients are inconsistent")
        items.append(FoodItemEstimate(name.strip(), portion.strip(), **values))
    if status is NutritionStatus.ESTIMATED and not assumptions:
        raise InvalidNutritionOutput("estimated result must disclose assumptions")
    return NutritionResult(status, tuple(items), tuple(assumptions), confidence, question)
