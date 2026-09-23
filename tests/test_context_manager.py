import unittest

from Gaoher.ai.agent.validation import InvalidContext
from Gaoher.ai.context.context_manager import ContextManager


class ContextManagerTests(unittest.TestCase):
    def test_selects_policy_fields_and_drops_unrelated_sensitive_top_level(self):
        available = {
            "tasks": [{"title": "Study"}],
            "exams": ["biology"],
            "nutrition": {"calories": 3},
            "api_key": "must not pass",
            "unknown": 4,
        }
        selected = ContextManager().select(available, category="omnia", policy="study")
        self.assertEqual(set(selected), {"exams", "tasks"})
        self.assertEqual(selected["tasks"][0]["title"], "Study")

    def test_context_is_deeply_immutable(self):
        selected = ContextManager().select(
            {"tasks": [{"title": "Study"}]}, category="action", policy="task_action"
        )
        with self.assertRaises(TypeError):
            selected["new"] = "value"
        with self.assertRaises(TypeError):
            selected["tasks"][0]["title"] = "changed"
        self.assertIsInstance(selected["tasks"], tuple)

    def test_context_policy_violations_are_rejected(self):
        with self.assertRaises(InvalidContext):
            ContextManager().select({"tasks": []}, category="general", policy="productivity")
        with self.assertRaises(InvalidContext):
            ContextManager().select({"tasks": []}, category="action", policy="study")
        with self.assertRaises(InvalidContext):
            ContextManager().select({"tasks": []}, category="omnia", policy="arbitrary_table")

    def test_oversized_context_is_rejected(self):
        with self.assertRaises(InvalidContext):
            ContextManager().select(
                {"study_progress": "x" * 9_000}, category="omnia", policy="study"
            )

    def test_malformed_nested_context_is_rejected(self):
        with self.assertRaises(InvalidContext):
            ContextManager().select(
                {"tasks": [{"api_key": "should never be context"}]},
                category="action", policy="task_action",
            )
        with self.assertRaises(InvalidContext):
            ContextManager().select(
                {"tasks": [object()]}, category="action", policy="task_action"
            )

    def test_general_policy_selects_nothing(self):
        self.assertEqual(ContextManager().select(
            {"goals": [1]}, category="general", policy="general"
        ), {})


if __name__ == "__main__":
    unittest.main()
