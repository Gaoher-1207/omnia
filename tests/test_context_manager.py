import unittest

from Gaoher.ai.agent.validation import InvalidContext
from Gaoher.ai.context.context_manager import AuthorizedContext, ContextManager


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

    def test_general_question_task_gets_no_context(self):
        self.assertEqual(ContextManager().select_task({"goals": [1]}, task="general"), {})

    def test_study_planning_receives_only_study_domains(self):
        selected = ContextManager().select_task({"study_progress": {"chapters": 2}, "tasks": [], "nutrition": {}}, task="study_planning")
        self.assertEqual(set(selected), {"study_progress", "tasks"})

    def test_nutrition_receives_only_nutrition_domains(self):
        selected = ContextManager().select_task({"nutrition": {"target": 2000}, "goals": {}, "tasks": []}, task="nutrition")
        self.assertEqual(set(selected), {"nutrition"})

    def test_progress_receives_progress_domains_only(self):
        selected = ContextManager().select_task({"study_progress": {}, "tasks": [], "activity": [], "goals": [], "preferences": {}}, task="progress_review")
        self.assertEqual(set(selected), {"study_progress", "tasks", "activity", "goals"})

    def test_task_action_receives_tasks_and_schedule_only(self):
        selected = ContextManager().select_task({"tasks": [], "schedule": [], "nutrition": {}}, task="task_action")
        self.assertEqual(set(selected), {"tasks", "schedule"})

    def test_unauthorized_domain_request_is_rejected(self):
        with self.assertRaises(InvalidContext):
            ContextManager().select_task({"nutrition": {}}, task="study_planning", requested_domains={"nutrition"})

    def test_unknown_domain_and_task_are_rejected(self):
        with self.assertRaises(InvalidContext):
            ContextManager().select_task({}, task="not_a_task")
        with self.assertRaises(InvalidContext):
            ContextManager().select_task({}, task="nutrition", requested_domains={"unregistered"})

    def test_sensitive_field_in_selected_domain_is_rejected(self):
        with self.assertRaises(InvalidContext):
            ContextManager().select_task({"nutrition": {"api_key": "secret"}}, task="nutrition")

    def test_size_and_nested_sensitive_limits_are_enforced(self):
        with self.assertRaises(InvalidContext):
            ContextManager().select_task({"nutrition": "x" * 9000}, task="nutrition")
        with self.assertRaises(InvalidContext):
            ContextManager().select_task({"tasks": [{"notes": {"internal_prompt": "hidden"}}]}, task="task_action")

    def test_two_user_context_is_request_scoped(self):
        manager = ContextManager()
        selected = manager.select_for_user(AuthorizedContext("alice", {"tasks": [{"title": "Alice task"}]}), user_id="alice", category="action", policy="task_action")
        self.assertEqual(selected.for_user("alice")["tasks"][0]["title"], "Alice task")
        with self.assertRaises(InvalidContext):
            selected.for_user("bob")
        with self.assertRaises(InvalidContext):
            manager.select_for_user(AuthorizedContext("alice", {}), user_id="bob", category="action", policy="task_action")

    def test_context_mutation_after_selection_cannot_change_snapshot(self):
        source = {"nutrition": {"items": ["rice"]}}
        selected = ContextManager().select_task(source, task="nutrition")
        source["nutrition"]["items"].append("cake")
        self.assertEqual(selected["nutrition"]["items"], ("rice",))

    def test_unrelated_domains_are_excluded(self):
        selected = ContextManager().select_task({"nutrition": {}, "goals": {}, "tasks": [], "api_key": "x"}, task="nutrition")
        self.assertEqual(set(selected), {"nutrition"})


if __name__ == "__main__":
    unittest.main()
