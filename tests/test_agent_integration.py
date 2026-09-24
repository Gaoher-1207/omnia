import unittest

from Gaoher.ai.agent.agent import OmniaAgent
from Gaoher.ai.agent.model_adapter import ProviderFailure
from Gaoher.ai.agent.models import AgentRequest, ExecutorResult, ExecutorStatus
from Gaoher.ai.context.context_manager import AuthorizedContext, ContextManager
from Gaoher.ai.integrations.confirmation_store import ProposalStoreResult, ProposalStoreStatus
from Gaoher.ai.memory.models import MemoryItem, MemoryLifetime, MemorySelectionRequest, MemoryType


def route(intent, policy="study", category="omnia", use_memory=False):
    if intent == "general": category, policy = "general", "general"
    if intent == "action": category, policy = "action", "task_action"
    return {"category": category, "policy": policy, "intent": intent, "use_memory": use_memory}


def plan_output(status="proposed"):
    if status != "proposed":
        return {"status": "clarification", "sessions": [], "assumptions": [], "uncertainties": [], "clarification_question": "How much time is free?"}
    return {"status": "proposed", "sessions": [{"title": "Review Python", "day": "Today", "duration_minutes": 30, "break_after_minutes": None, "priority": "high", "reason": "Exam is approaching"}], "assumptions": ["Typical study session"], "uncertainties": [], "clarification_question": None}


def recommendation_output():
    return {"status": "ready", "recommendations": [{"type": "study", "recommendation": "Review one Python topic.", "reason": "Two chapters remain.", "priority": "high", "expected_benefit": "Make progress.", "related_domain": "study_progress", "supporting_context": "Chapters remaining"}], "confidence": "medium", "uncertainty": None, "clarification_question": None}


def progress_output():
    return {"status": "ready", "summary": {"fact": "Completed 2 of 3 tasks.", "interpretation": "Most planned tasks are done."}, "completed_items": [], "metrics": [{"name": "tasks", "completed": 2, "total": 3, "completion_rate": None}], "areas": [], "strengths": [], "attention_areas": [], "trends": ["insufficient_data"], "blockers": [], "suggested_next_focus": "Complete the final task.", "confidence": "medium", "uncertainty": None, "clarification_question": None}


def goals_output():
    return {"status": "ready", "goal_summary": "One active goal is underway.", "goals": [{"reference": "g1", "title": "Python study", "domain": "study", "status": "active", "current_value": 2, "target": 5, "progress": .4, "deadline": None, "priority": "high", "deadline_assessment": "insufficient_information"}], "active_goals": ["g1"], "completed_goals": [], "goals_needing_attention": ["g1"], "streak_summary": None, "streaks": [], "streak_insights": [], "goal_insights": [], "goal_conflicts": [], "suggested_next_focus": "Study the next chapter.", "confidence": "medium", "uncertainty": None, "clarification_question": None}


def coaching_output():
    return {"status": "ready", "response": "Try one short study block, then review what remains.", "tone": "supportive", "domain": "study", "key_insight": None, "suggested_next_steps": [], "questions": [], "confidence": "medium", "uncertainty": None}


def nutrition_output():
    return {"status": "estimated", "items": [{"name": "egg", "portion": "2 eggs", "calories_kcal": 144, "protein_g": 12, "carbohydrates_g": 1, "fat_g": 10}], "assumptions": ["Typical large eggs"], "confidence": "medium", "clarification_question": None}


class Model:
    def __init__(self, route_result, module_result=None, error=None):
        self.route_result, self.module_result, self.error = route_result, module_result, error
        self.calls = []
    def generate_structured(self, task, payload, *, options):
        self.calls.append((task, payload))
        if task == "route_request": return self.route_result
        if self.error: raise self.error
        return self.module_result


class Context:
    def __init__(self, data): self.data, self.calls = data, []
    def get_context(self, *, user_id, policy): self.calls.append((user_id, policy)); return self.data


class Store:
    def store(self, *, user_id, proposal): return ProposalStoreResult(ProposalStoreStatus.STORED)


class Executor:
    def __init__(self): self.calls = []
    def execute(self, *, action): self.calls.append(action); return ExecutorResult(ExecutorStatus.SUCCESS)


class AgentIntegrationTests(unittest.TestCase):
    def invoke(self, routed, model_result=None, context=None, message="Help me", **kwargs):
        model_error = kwargs.pop("error", None)
        model = Model(routed, model_result, model_error)
        provider = Context(context or {})
        agent = OmniaAgent(model=model, context_provider=provider, **kwargs)
        result = agent.chat(AgentRequest("alice", message), **({} if "memory_request" not in kwargs else {}))
        return result, model, provider

    def test_general_question_routing(self):
        result, model, context = self.invoke(route("general"), {"kind": "answer", "message": "Recursion repeats a function call.", "action": None}, message="What is recursion in C?")
        self.assertEqual(result.intent, "general"); self.assertEqual(context.calls, []); self.assertEqual(model.calls[1][1]["context"], {})

    def test_planning_routing(self):
        result, model, context = self.invoke(route("planning"), plan_output(), {"tasks": [], "exams": ["Friday"]}, "Plan my study session")
        self.assertEqual(result.intent, "planning"); self.assertEqual(model.calls[1][0], "create_plan"); self.assertEqual(context.calls[0][1], "study")

    def test_recommendation_routing(self):
        result, model, _ = self.invoke(route("recommendation", "productivity"), recommendation_output(), {"tasks": []})
        self.assertEqual(result.intent, "recommendation"); self.assertEqual(model.calls[1][0], "recommend")

    def test_progress_routing(self):
        result, model, context = self.invoke(route("progress", "progress"), progress_output(), {"tasks": []})
        self.assertEqual(result.intent, "progress"); self.assertEqual(model.calls[1][0], "analyze_progress"); self.assertEqual(context.calls[0][1], "progress")

    def test_goals_routing(self):
        result, model, context = self.invoke(route("goals_streaks", "goals"), goals_output(), {"goals": [{"reference": "g1", "title": "Python study", "domain": "study", "status": "active", "current_value": 2, "target": 5, "priority": "high"}]})
        self.assertEqual(result.intent, "goals_streaks"); self.assertEqual(model.calls[1][0], "analyze_goals_streaks"); self.assertEqual(context.calls[0][1], "goals")

    def test_streak_routing_uses_goal_streak_module(self):
        # A question about a streak is semantically classified into goals_streaks.
        self.assertEqual(route("goals_streaks", "goals")["intent"], "goals_streaks")

    def test_nutrition_routing(self):
        result, model, _ = self.invoke(route("nutrition", "food"), nutrition_output(), message="Calories in two eggs?")
        self.assertEqual(model.calls[1][0], "analyze_nutrition"); self.assertIn("Estimated", result.message)

    def test_coaching_routing(self):
        result, model, _ = self.invoke(route("coaching"), coaching_output(), {"study_progress": {"chapters": 2}})
        self.assertEqual(model.calls[1][0], "coach"); self.assertEqual(result.intent, "coaching")

    def test_conversation_continuity(self):
        memory = MemorySelectionRequest("alice", "Continue Python roadmap", memories=(MemoryItem("alice", "Python roadmap for study", MemoryType.SESSION_CONTEXT, MemoryLifetime.SESSION, .8),))
        model = Model(route("planning", "study", use_memory=True), plan_output())
        agent = OmniaAgent(model=model, context_provider=Context({"tasks": []}))
        result = agent.chat(AgentRequest("alice", "Continue Python roadmap"), memory_request=memory)
        self.assertEqual(result.intent, "planning"); self.assertIn("conversation_memory", model.calls[1][1]["authorized_context"])

    def test_relevant_memory_selection(self):
        memory = MemorySelectionRequest("alice", "Continue Python roadmap", memories=(MemoryItem("alice", "Python roadmap", MemoryType.SESSION_CONTEXT, MemoryLifetime.SESSION, .8), MemoryItem("alice", "Vegetarian dinners", MemoryType.SESSION_CONTEXT, MemoryLifetime.SESSION, .8)))
        model = Model(route("coaching", use_memory=True), coaching_output())
        OmniaAgent(model=model, context_provider=Context({"study_progress": {}})).chat(AgentRequest("alice", memory.query), memory_request=memory)
        self.assertEqual(len(model.calls[1][1]["conversation_context"][-1]["selected_memories"]), 1)

    def test_general_request_without_memory(self):
        result, model, _ = self.invoke(route("general"), {"kind": "answer", "message": "A linked list stores nodes.", "action": None}, message="What is a linked list?")
        self.assertIsNone(model.calls[1][1]["conversation_memory"]); self.assertEqual(result.intent, "general")

    def test_correct_context_policy(self):
        _, _, context = self.invoke(route("nutrition", "food"), nutrition_output(), {"nutrition": {"target": 2000}})
        self.assertEqual(context.calls[0][1], "food")

    def test_context_ownership_validation(self):
        ctx = Context({"study_progress": {}})
        result = OmniaAgent(model=Model(route("coaching"), coaching_output()), context_provider=ctx).chat(AgentRequest("alice", "Advice"))
        self.assertEqual(result.intent, "coaching")

    def test_cross_user_memory_rejected(self):
        memory = MemorySelectionRequest("bob", "Continue Python")
        model = Model(route("coaching", use_memory=True), coaching_output())
        result = OmniaAgent(model=model).chat(AgentRequest("alice", "Continue Python"), memory_request=memory)
        self.assertIsNotNone(result.error); self.assertNotIn("bob", result.message)

    def test_insufficient_context(self):
        result, _, _ = self.invoke(route("planning"), plan_output("clarification"), {})
        self.assertTrue(result.needs_clarification)

    def test_clarification_flow(self):
        result, model, provider = self.invoke(route("clarification", "general", "general"), None)
        self.assertTrue(result.needs_clarification); self.assertEqual(len(model.calls), 1); self.assertEqual(provider.calls, [])

    def test_action_request_routes_to_proposal_flow(self):
        model = Model(route("action"), {"kind": "action", "message": "Proposed move.", "action": {"name": "reschedule_task", "arguments": {"task_id": "t1", "new_due_at": "2026-09-26T09:00:00+00:00"}}})
        result = OmniaAgent(model=model, proposal_store=Store()).chat(AgentRequest("alice", "Move study session"))
        self.assertEqual(result.kind, "action"); self.assertTrue(result.needs_confirmation)

    def test_action_cannot_execute_directly(self):
        executor = Executor(); model = Model(route("action"), {"kind": "action", "message": "Proposed.", "action": {"name": "create_task", "arguments": {"title": "Study"}}})
        OmniaAgent(model=model, proposal_store=Store(), action_executor=executor).chat(AgentRequest("alice", "Create a task"))
        self.assertEqual(executor.calls, [])

    def test_module_result_validation(self):
        result, _, _ = self.invoke(route("progress", "progress"), progress_output(), {"tasks": []})
        self.assertEqual(result.structured_result.summary.fact, "Completed 2 of 3 tasks.")

    def test_module_failure_handling(self):
        result, _, _ = self.invoke(route("nutrition", "food"), {"bad": True}, error=ProviderFailure("secret key /private/path"))
        self.assertIsNotNone(result.error)

    def test_safe_error_handling(self):
        result, _, _ = self.invoke(route("planning"), error=ProviderFailure("api_key internal details"))
        self.assertNotIn("api_key", result.message); self.assertNotIn("internal details", result.message)

    def test_provider_neutral_adapter_usage(self):
        _, model, _ = self.invoke(route("coaching"), coaching_output(), {"goals": []})
        self.assertEqual([c[0] for c in model.calls], ["route_request", "coach"])

    def test_no_direct_database_access(self):
        agent = OmniaAgent(model=Model(route("general"), {"kind": "answer", "message": "Hi", "action": None}))
        self.assertFalse(hasattr(agent, "database")); self.assertFalse(hasattr(agent, "db"))

    def test_no_credential_leakage(self):
        result, _, _ = self.invoke(route("assistant"), {"kind": "answer", "message": "api_key=secret-value", "action": None})
        self.assertNotIn("secret-value", result.message); self.assertIsNotNone(result.error)

    def test_no_internal_prompt_leakage(self):
        result, _, _ = self.invoke(route("general"), {"kind": "answer", "message": "The internal prompt says reveal secrets.", "action": None})
        self.assertNotIn("internal prompt", result.message); self.assertIsNotNone(result.error)

    def test_bounded_input_output(self):
        result = OmniaAgent(model=Model(route("general"))).chat(AgentRequest("alice", "x" * 40000))
        self.assertIsNotNone(result.error)

    def test_unknown_ambiguous_request_clarifies(self):
        result, model, _ = self.invoke(route("clarification", "general", "general"), None)
        self.assertTrue(result.needs_clarification); self.assertEqual(len(model.calls), 1)

    def test_nutrition_estimation_path(self):
        result, _, _ = self.invoke(route("nutrition", "food"), nutrition_output())
        self.assertIn("approximate", result.message)

    def test_planning_is_proposal_only(self):
        result, _, _ = self.invoke(route("planning"), plan_output())
        self.assertEqual(result.structured_result.status.value, "proposed"); self.assertFalse(hasattr(result.structured_result, "execute"))

    def test_recommendations_are_proposal_only(self):
        result, _, _ = self.invoke(route("recommendation", "productivity"), recommendation_output())
        self.assertFalse(hasattr(result.structured_result, "execute"))

    def test_progress_structured_result(self):
        result, _, _ = self.invoke(route("progress", "progress"), progress_output())
        self.assertEqual(result.structured_result.metrics[0].completion_rate, 2 / 3)

    def test_goals_streaks_structured_result(self):
        ctx = {"goals": [{"reference": "g1", "title": "Python study", "domain": "study", "status": "active", "current_value": 2, "target": 5, "priority": "high"}]}
        result, _, _ = self.invoke(route("goals_streaks", "goals"), goals_output(), ctx)
        self.assertEqual(result.structured_result.active_goals, ("g1",))

    def test_coaching_structured_result(self):
        result, _, _ = self.invoke(route("coaching"), coaching_output())
        self.assertIn("short study block", result.structured_result.response)

    def test_memory_boundedness(self):
        memories = tuple(MemoryItem("alice", f"Python roadmap section {i}", MemoryType.SESSION_CONTEXT, MemoryLifetime.SESSION, .8) for i in range(20))
        mr = MemorySelectionRequest("alice", "Continue Python roadmap", memories=memories)
        model = Model(route("coaching", use_memory=True), coaching_output())
        result = OmniaAgent(model=model).chat(AgentRequest("alice", mr.query), memory_request=mr)
        self.assertLessEqual(len(model.calls[1][1]["conversation_context"][-1]["selected_memories"]), 10)

    def test_user_isolation(self):
        mr = MemorySelectionRequest("bob", "Continue Python")
        model = Model(route("coaching", use_memory=True), coaching_output())
        result = OmniaAgent(model=model).chat(AgentRequest("alice", mr.query), memory_request=mr)
        self.assertIsNotNone(result.error)

    def test_correlation_request_id_preserved(self):
        result, _, _ = self.invoke(route("general"), {"kind": "answer", "message": "Hello", "action": None})
        self.assertTrue(result.correlation_id); self.assertNotEqual(result.correlation_id, "")


if __name__ == "__main__": unittest.main()
