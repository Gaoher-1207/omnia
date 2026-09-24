import unittest

from Gaoher.ai.agent.validation import InvalidModelOutput, validate_assistant_result, validate_route


class ValidationTests(unittest.TestCase):
    def test_rejects_unregistered_action(self):
        with self.assertRaises(InvalidModelOutput):
            validate_assistant_result({
                "kind": "action", "message": "Do it", "action": {"name": "delete_all", "arguments": {}}
            }, allowed_action_names=frozenset({"create_task"}))

    def test_rejects_unknown_action_arguments(self):
        with self.assertRaises(InvalidModelOutput):
            validate_assistant_result({
                "kind": "action", "message": "Create", "action": {
                    "name": "create_task", "arguments": {"title": "Study", "user_id": "other"}
                }
            }, allowed_action_names=frozenset({"create_task"}))

    def test_general_route_cannot_select_omnia_policy(self):
        with self.assertRaises(InvalidModelOutput):
            validate_route({"category": "general", "policy": "study"})

    def test_route_has_one_backend_policy_not_a_domain_list(self):
        with self.assertRaises(InvalidModelOutput):
            validate_route({"category": "omnia", "policy": ["study", "food"]})

    def test_action_must_be_allowed_by_route(self):
        action_result = {
                "kind": "action", "message": "Create", "action": {
                "name": "create_task", "arguments": {"title": "Study"}
            }
        }
        with self.assertRaises(InvalidModelOutput):
            validate_assistant_result(action_result)

    def test_rejects_oversized_response_message(self):
        with self.assertRaises(InvalidModelOutput):
            validate_assistant_result({
                "kind": "answer", "message": "x" * 8_001, "action": None
            })


if __name__ == "__main__":
    unittest.main()
