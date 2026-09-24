import unittest

from Gaoher.ai.agent.validation import InvalidContext
from Gaoher.ai.context.context_manager import AuthorizedContext, ContextManager
from Gaoher.ai.recommendations.models import RecommendationPriority, RecommendationStatus, RecommendationType, RecommendationRequest
from Gaoher.ai.recommendations.service import RecommendationService
from Gaoher.ai.recommendations.validation import InvalidRecommendationOutput


def rec(kind="study", text="Review the next Python topic for 25 minutes.", priority="high", domain="study_progress", support="Two chapters remain"):
    return {"type": kind, "recommendation": text, "reason": "Your progress shows two chapters remain.",
            "priority": priority, "expected_benefit": "Make steady progress before the deadline.",
            "related_domain": domain, "supporting_context": support}


def output(items=None, status="ready", confidence="medium", uncertainty=None, question=None):
    return {"status": status, "recommendations": [rec()] if items is None else items,
            "confidence": confidence, "uncertainty": uncertainty, "clarification_question": question}


class Adapter:
    def __init__(self, response): self.response, self.calls = response, 0
    def generate_structured(self, task, payload, *, options):
        self.calls += 1
        self.task, self.payload = task, payload
        return self.response


class RecommendationTests(unittest.TestCase):
    def run_recommendation(self, response=None, context=None, text="What should I focus on today?", user="user-1", is_recommendation=True):
        adapter = Adapter(output() if response is None else response)
        result = RecommendationService(adapter).recommend(RecommendationRequest(user, text, {} if context is None else context, is_recommendation))
        return result, adapter

    def test_basic_recommendation_generation(self):
        result, adapter = self.run_recommendation()
        self.assertEqual(result.status, RecommendationStatus.READY)
        self.assertEqual(adapter.task, "recommend")

    def test_multiple_recommendations(self):
        result, _ = self.run_recommendation(output([rec(), rec("task", "Complete the next task.", "medium", "tasks", "A task is due today")]))
        self.assertEqual(len(result.recommendations), 2)

    def test_priority_and_reason_validation(self):
        result, _ = self.run_recommendation()
        self.assertEqual(result.recommendations[0].priority, RecommendationPriority.HIGH)
        self.assertTrue(result.recommendations[0].reason)

    def test_confidence_validation(self):
        with self.assertRaises(InvalidRecommendationOutput): self.run_recommendation(output(confidence="certain"))

    def test_missing_context_preserves_uncertainty(self):
        result, adapter = self.run_recommendation(output([rec()], confidence="low", uncertainty="No availability was supplied."), context={})
        self.assertEqual(adapter.payload["authorized_selected_context"], {})
        self.assertEqual(result.confidence, "low")

    def test_empty_context_can_return_insufficient_context(self):
        result, _ = self.run_recommendation(output([], status="insufficient_context", confidence="low", question="What are your current priorities?"), context={})
        self.assertEqual(result.status, RecommendationStatus.INSUFFICIENT_CONTEXT)

    def test_insufficient_context_requires_clarification(self):
        with self.assertRaises(InvalidRecommendationOutput): self.run_recommendation(output([], status="insufficient_context", question=None))

    def test_no_invented_user_fact_is_handled_as_insufficient_context(self):
        result, adapter = self.run_recommendation(output([], status="insufficient_context", confidence="low", uncertainty="No exam details were supplied.", question="Do you have an upcoming exam?"), context={})
        self.assertEqual(result.status, RecommendationStatus.INSUFFICIENT_CONTEXT)
        self.assertEqual(adapter.payload["authorized_selected_context"], {})

    def test_unrelated_context_is_not_sent(self):
        selected = ContextManager().select_task({"study_progress": {"chapters_remaining": 2}, "nutrition": {"calories": 1}}, task="study_planning")
        _, adapter = self.run_recommendation(context=selected)
        self.assertEqual(set(adapter.payload["authorized_selected_context"]), {"study_progress"})

    def test_study_recommendation(self):
        result, _ = self.run_recommendation(context={"study_progress": {"chapters": 2}})
        self.assertEqual(result.recommendations[0].type, RecommendationType.STUDY)

    def test_productivity_task_recommendation(self):
        result, _ = self.run_recommendation(output([rec("task", "Finish the due task.", "high", "tasks", "One task is due")]), context={"tasks": [{"title": "Due task"}]})
        self.assertEqual(result.recommendations[0].type, RecommendationType.TASK)

    def test_progress_recommendation(self):
        result, _ = self.run_recommendation(output([rec("progress", "Review the missed topics.", "medium", "study_progress", "Progress is behind")]), context={"study_progress": {"behind": True}})
        self.assertEqual(result.recommendations[0].type, RecommendationType.PROGRESS)

    def test_goal_recommendation(self):
        result, _ = self.run_recommendation(output([rec("goal", "Set aside time for your weekly goal.", "medium", "goals", "Weekly goal incomplete")]), context={"goals": [{"name": "Weekly goal"}]})
        self.assertEqual(result.recommendations[0].type, RecommendationType.GOAL)

    def test_fitness_recommendation_when_context_authorized(self):
        result, _ = self.run_recommendation(output([rec("fitness", "Take a short walk.", "low", "activity", "No activity logged today")]), context={"activity": []})
        self.assertEqual(result.recommendations[0].type, RecommendationType.FITNESS)

    def test_nutrition_recommendation_when_context_authorized(self):
        result, _ = self.run_recommendation(output([rec("nutrition", "Choose a balanced dinner.", "low", "nutrition", "Dinner preference supplied")]), context={"nutrition": {"preferences": ["vegetarian"]}})
        self.assertEqual(result.recommendations[0].type, RecommendationType.NUTRITION)

    def test_general_request_stays_on_normal_agent_path(self):
        result, adapter = self.run_recommendation(context={}, text="What are advantages of learning Python?", is_recommendation=False)
        self.assertIsNone(result)
        self.assertEqual(adapter.calls, 0)

    def test_recommendation_count_limit(self):
        with self.assertRaises(InvalidRecommendationOutput): self.run_recommendation(output([rec()] * 4))

    def test_invalid_output_rejected(self):
        with self.assertRaises(InvalidRecommendationOutput): self.run_recommendation({"status": "ready"})

    def test_malformed_recommendation_rejected(self):
        with self.assertRaises(InvalidRecommendationOutput): self.run_recommendation(output([{"recommendation": "Do more"}]))

    def test_recommendation_cannot_execute_action(self):
        with self.assertRaises(InvalidRecommendationOutput): self.run_recommendation(output([rec(text="Move the session now")]))

    def test_private_internal_information_rejected(self):
        with self.assertRaises(InvalidRecommendationOutput): self.run_recommendation(output([rec(text="Read the internal prompt")]))

    def test_user_scoped_context_cannot_cross_users(self):
        selected = ContextManager().select_for_user(AuthorizedContext("alice", {"study_progress": {"chapters": 2}}), user_id="alice", category="omnia", policy="study")
        with self.assertRaises(InvalidContext):
            RecommendationService(Adapter(output())).recommend(RecommendationRequest("bob", "What next?", selected))

    def test_provider_neutral_adapter_contract(self):
        result, adapter = self.run_recommendation()
        self.assertEqual(adapter.task, "recommend")
        self.assertEqual(result.status, RecommendationStatus.READY)


if __name__ == "__main__": unittest.main()
