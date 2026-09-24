import unittest

from Gaoher.ai.agent.validation import InvalidContext
from Gaoher.ai.context.context_manager import AuthorizedContext, ContextManager
from Gaoher.ai.coaching.models import CoachingRequest, CoachingRequestType, CoachingStatus
from Gaoher.ai.coaching.service import CoachingService
from Gaoher.ai.coaching.validation import InvalidCoachingOutput


def response(status="ready", **overrides):
    value = {"status": status, "response": "You completed the planned workout. Consider a short recovery walk if that fits your energy today.",
        "tone": "supportive", "domain": "fitness", "key_insight": {"text": "A useful next step can be chosen.", "supporting_reference": None},
        "suggested_next_steps": [{"suggestion": "Choose one small recovery activity.", "reason": "A manageable next step can help maintain routine.", "related_domain": "fitness"}],
        "questions": [], "confidence": "medium", "uncertainty": None}
    if status != "ready":
        value.update(response="I would need your recent progress to answer that personally.", domain=None, key_insight=None,
                     suggested_next_steps=[], questions=[{"question": "Can you share your recent progress?"}], confidence="low",
                     uncertainty="No progress context was supplied.")
    value.update(overrides)
    return value


class Adapter:
    def __init__(self, result): self.result, self.calls = result, 0
    def generate_structured(self, task, payload, *, options):
        self.calls += 1; self.task, self.payload = task, payload
        return self.result


def selected(values, user="alice", policy="progress", category="omnia"):
    return ContextManager().select_for_user(AuthorizedContext(user, values), user_id=user, category=category, policy=policy)


class CoachingTests(unittest.TestCase):
    def coach(self, result=None, context=None, request_type=CoachingRequestType.COACHING, conversation=(), user="alice", text="What should I do next?", policy="progress"):
        adapter = Adapter(response() if result is None else result)
        ctx = selected({} if context is None else context, user=user, policy=policy)
        output = CoachingService(adapter).coach(CoachingRequest(user, text, ctx, request_type, conversation))
        if request_type is not CoachingRequestType.GENERAL:
            self.assertEqual(adapter.task, "coach"); self.assertNotIn("user_id", adapter.payload)
        return output, adapter

    def test_basic_coaching_response(self):
        result, _ = self.coach(context={"activity": [{"workout": "complete"}]})
        self.assertEqual(result.status, CoachingStatus.READY)

    def test_study_coaching(self):
        _, adapter = self.coach(context={"study_progress": {"chapters_remaining": 2}}, text="I'm behind on Python")
        self.assertIn("study_progress", adapter.payload["authorized_selected_context"])

    def test_productivity_coaching(self):
        _, adapter = self.coach(context={"tasks": [{"title": "Review notes"}]})
        self.assertIn("tasks", adapter.payload["authorized_selected_context"])

    def test_fitness_coaching(self):
        result, _ = self.coach(context={"activity": [{"workout": "complete"}]})
        self.assertEqual(result.domain, "fitness")

    def test_goal_coaching(self):
        _, adapter = self.coach(context={"goals": [{"title": "Study daily"}]}, text="I missed my goal today")
        self.assertIn("goals", adapter.payload["authorized_selected_context"])

    def test_streak_coaching(self):
        _, adapter = self.coach(context={"streaks": [{"current_streak": 2}]}, text="I keep breaking my streak")
        self.assertIn("streaks", adapter.payload["authorized_selected_context"])

    def test_progress_based_coaching(self):
        result, _ = self.coach(context={"study_progress": {"completed": 3}})
        self.assertIsNotNone(result.key_insight)

    def test_deadline_aware_coaching(self):
        _, adapter = self.coach(context={"exams": [{"subject": "Python", "deadline": "Friday"}], "tasks": []}, policy="study")
        self.assertIn("exams", adapter.payload["authorized_selected_context"])

    def test_general_coaching_without_omnia_context(self):
        result, adapter = self.coach(context={}, text="Give me some general advice for today")
        self.assertEqual(result.status, CoachingStatus.READY)
        self.assertEqual(adapter.payload["authorized_selected_context"], {})

    def test_general_knowledge_request_bypasses_coaching(self):
        result, adapter = self.coach(context={}, text="What is machine learning?", request_type=CoachingRequestType.GENERAL)
        self.assertIsNone(result); self.assertEqual(adapter.calls, 0)

    def test_insufficient_context(self):
        result, _ = self.coach(response("insufficient_context"), context={}, text="Why am I falling behind?")
        self.assertEqual(result.status, CoachingStatus.INSUFFICIENT_CONTEXT)

    def test_clarification_question(self):
        result, _ = self.coach(response("clarification"), context={})
        self.assertEqual(result.questions[0].question, "Can you share your recent progress?")

    def test_context_ownership_validation(self):
        with self.assertRaises(InvalidContext):
            CoachingService(Adapter(response())).coach(CoachingRequest("bob", "Advice?", selected({"goals": []})))

    def test_unrelated_context_excluded(self):
        ctx = selected({"activity": [], "nutrition": {"calories": 2000}}, policy="fitness")
        adapter = Adapter(response()); CoachingService(adapter).coach(CoachingRequest("alice", "Workout advice?", ctx))
        self.assertEqual(set(adapter.payload["authorized_selected_context"]), {"activity"})

    def test_no_invented_user_facts_reference_must_exist(self):
        bad = response(key_insight={"text": "An exam is tomorrow.", "supporting_reference": "exams"})
        with self.assertRaises(InvalidCoachingOutput): self.coach(bad, context={"tasks": []})

    def test_unsupported_psychological_claim_rejected(self):
        with self.assertRaises(InvalidCoachingOutput): self.coach(response(response="You are definitely feeling lazy because you missed a goal."))

    def test_medical_diagnosis_rejected(self):
        with self.assertRaises(InvalidCoachingOutput): self.coach(response(response="You have depression."))

    def test_dangerous_advice_rejected(self):
        with self.assertRaises(InvalidCoachingOutput): self.coach(response(response="Work out through severe pain to keep your streak."))

    def test_action_request_cannot_execute(self):
        result, _ = self.coach(response(), request_type=CoachingRequestType.ACTION, text="Move tomorrow's study session to Saturday")
        self.assertEqual(result.status, CoachingStatus.READY)
        with self.assertRaises(InvalidCoachingOutput): self.coach(response(response="I moved your session to Saturday."), request_type=CoachingRequestType.ACTION)

    def test_suggested_next_steps(self):
        result, _ = self.coach(); self.assertEqual(len(result.suggested_next_steps), 1)

    def test_insight_generation(self):
        result, _ = self.coach(context={"activity": []}); self.assertIsNotNone(result.key_insight)

    def test_confidence_validation(self):
        with self.assertRaises(InvalidCoachingOutput): self.coach(response(confidence="certain"))

    def test_uncertainty_handling(self):
        result, _ = self.coach(response("insufficient_context")); self.assertIn("No progress context", result.uncertainty)

    def test_invalid_model_output(self):
        with self.assertRaises(InvalidCoachingOutput): self.coach({"status": "ready"})

    def test_unsupported_fields(self):
        bad = response(); bad["internal_prompt"] = "secret"
        with self.assertRaises(InvalidCoachingOutput): self.coach(bad)

    def test_sensitive_internal_information_excluded(self):
        with self.assertRaises(InvalidCoachingOutput): self.coach(response(response="The API_KEY is xyz"))

    def test_user_isolation(self):
        ctx = selected({"activity": []}, user="alice")
        with self.assertRaises(InvalidContext): CoachingService(Adapter(response())).coach(CoachingRequest("bob", "Advice?", ctx))

    def test_provider_neutral_behavior(self):
        _, adapter = self.coach(); self.assertEqual(adapter.task, "coach")

    def test_response_length_limit(self):
        with self.assertRaises(InvalidCoachingOutput): self.coach(response(response="x" * 1601))

    def test_empty_context(self):
        result, adapter = self.coach(response("insufficient_context"), context={})
        self.assertEqual(adapter.payload["authorized_selected_context"], {}); self.assertEqual(result.status, CoachingStatus.INSUFFICIENT_CONTEXT)

    def test_optional_conversation_context(self):
        _, adapter = self.coach(conversation=({"role": "user", "content": "I missed yesterday"},))
        self.assertEqual(len(adapter.payload["conversation_context"]), 1)

    def test_conversation_context_size_limit(self):
        with self.assertRaises((InvalidContext, ValueError)): self.coach(conversation=({"message": "x" * 9000},))
        with self.assertRaises(ValueError): CoachingRequest("alice", "Advice", selected({}), conversation_context=tuple({"content": "ok"} for _ in range(9)))

    def test_no_persistent_memory_created(self):
        _, adapter = self.coach(conversation=({"role": "user", "content": "temporary"},))
        self.assertFalse(hasattr(adapter, "store"))

    def test_coaching_cannot_modify_goals(self):
        result, _ = self.coach(context={"goals": []}); self.assertFalse(hasattr(result, "update_goal"))

    def test_coaching_cannot_modify_tasks(self):
        result, _ = self.coach(context={"tasks": []}); self.assertFalse(hasattr(result, "create_task"))

    def test_coaching_cannot_modify_schedules(self):
        result, _ = self.coach(context={"schedule": []}); self.assertFalse(hasattr(result, "move_event"))


if __name__ == "__main__": unittest.main()
