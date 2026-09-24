import unittest

from Gaoher.ai.food.calorie_estimation import (
    Confidence, InvalidNutritionOutput, NutritionRequest, NutritionStatus,
)
from Gaoher.ai.food.nutrition_analysis import NutritionAnalysisService


def item(name="apple", portion="1 medium apple", calories=95, protein=0.5, carbs=25, fat=0.3):
    return {"name": name, "portion": portion, "calories_kcal": calories,
            "protein_g": protein, "carbohydrates_g": carbs, "fat_g": fat}


def result(items=None, status="estimated", assumptions=None, confidence="medium", question=None):
    return {"status": status, "items": [item()] if items is None else items,
            "assumptions": ["Typical medium serving assumed"] if assumptions is None else assumptions,
            "confidence": confidence, "clarification_question": question}


class StubAdapter:
    def __init__(self, output): self.output = output
    def generate_structured(self, task, payload, *, options):
        self.task, self.payload = task, payload
        return self.output


class NutritionAnalysisTests(unittest.TestCase):
    def analyze(self, output, text="I ate an apple"):
        adapter = StubAdapter(output)
        value = NutritionAnalysisService(adapter).analyze(NutritionRequest(text))
        self.assertEqual(adapter.task, "analyze_nutrition")
        self.assertEqual(adapter.payload["food_description"], text)
        return value

    def test_single_food_item(self):
        value = self.analyze(result())
        self.assertEqual(len(value.items), 1)
        self.assertEqual(value.totals["calories_kcal"], 95)

    def test_multiple_food_items(self):
        value = self.analyze(result([item(), item("yogurt", "1 cup", 150, 8, 12, 7)]))
        self.assertEqual(len(value.items), 2)
        self.assertEqual(value.totals["calories_kcal"], 245)

    def test_missing_portion_information_asks_clarification(self):
        value = self.analyze(result([], 
                 status="clarification", assumptions=["Portion size materially changes estimate"],
                 question="How much curry did you eat?"), "I ate curry")
        self.assertEqual(value.status, NutritionStatus.CLARIFICATION)
        self.assertIsNone(value.totals)
        self.assertTrue(value.clarification_question)

    def test_explicit_portion_information(self):
        value = self.analyze(result([item("rice", "200 g cooked", 260, 5, 57, .6)]), "I ate 200 g cooked rice")
        self.assertEqual(value.items[0].portion, "200 g cooked")

    def test_unclear_food_description(self):
        value = self.analyze(result([], status="unclear", assumptions=[], confidence="low",
                                    question="What food do you mean?"), "I ate that thing")
        self.assertEqual(value.status, NutritionStatus.UNCLEAR)

    def test_malformed_ai_output_rejected(self):
        with self.assertRaises(InvalidNutritionOutput): self.analyze({"status": "estimated"})

    def test_unrealistic_nutrition_values_rejected(self):
        with self.assertRaises(InvalidNutritionOutput): self.analyze(result([item(calories=100000)]))

    def test_result_uses_estimated_wording(self):
        value = self.analyze(result())
        self.assertTrue(value.estimated)
        self.assertIn("Estimated", value.wording)
        self.assertIn("not an exact measurement", value.wording)


if __name__ == "__main__": unittest.main()
