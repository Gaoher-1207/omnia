import unittest
from datetime import datetime, timedelta, timezone

from Gaoher.ai.agent.agent import OmniaAgent
from Gaoher.ai.agent.model_adapter import ModelIntegrationPending, PendingModelAdapter
from Gaoher.ai.agent.models import (
    ActionProposal, AgentRequest, ConfirmedAction, ExecutorResult, ExecutorStatus,
)
from Gaoher.ai.integrations.confirmation_store import ProposalStoreResult, ProposalStoreStatus


class FakeModel:
    def __init__(self, outputs):
        self.outputs = iter(outputs)
        self.calls = []

    def generate_structured(self, task, payload, *, options):
        self.calls.append((task, payload, options))
        value = next(self.outputs)
        if isinstance(value, Exception):
            raise value
        return value


class FakeContext:
    def __init__(self, data):
        self.data = data
        self.requests = []

    def get_context(self, *, user_id, policy):
        self.requests.append((user_id, policy))
        return self.data


class MemoryProposalStore:
    """Test double only. Production persistence/atomicity belongs to Django."""

    def __init__(self, token="opaque-confirmation-token"):
        self.token = token
        self.proposals = {}
        self.used = set()

    def store(self, *, user_id, proposal):
        self.proposals[proposal.proposal_id] = (user_id, proposal)
        return ProposalStoreResult(ProposalStoreStatus.STORED)

    def claim(self, *, user_id, proposal_id, confirmation_token, now):
        item = self.proposals.get(proposal_id)
        if item is None or item[0] != user_id or confirmation_token != self.token:
            return ProposalStoreResult(ProposalStoreStatus.REJECTED)
        if proposal_id in self.used or item[1].expires_at <= now:
            return ProposalStoreResult(ProposalStoreStatus.REJECTED)
        self.used.add(proposal_id)
        proposal = item[1]
        return ProposalStoreResult(ProposalStoreStatus.CLAIMED, ConfirmedAction(
            user_id=user_id,
            proposal=proposal,
            confirmation_receipt="trusted-receipt",
            idempotency_key=f"omnia-action:{proposal_id}",
        ))


class FakeExecutor:
    def __init__(self, result=None, error=None):
        self.result = result or ExecutorResult(ExecutorStatus.SUCCESS)
        self.error = error
        self.calls = []

    def execute(self, *, action):
        self.calls.append(action)
        if self.error:
            raise self.error
        return self.result


def action_model():
    return FakeModel([
        {"category": "action", "policy": "task_action"},
        {"kind": "action", "message": "I can create that task.", "action": {
            "name": "create_task", "arguments": {"title": "Revise biology"}
        }},
    ])


class AgentTests(unittest.TestCase):
    def test_general_question_uses_no_omnia_context(self):
        model = FakeModel([
            {"category": "general", "policy": "general"},
            {"kind": "answer", "message": "Dreams are associated with sleep processes.", "action": None},
        ])
        context = FakeContext({"tasks": ["private"]})
        result = OmniaAgent(model=model, context_provider=context).chat(
            AgentRequest("user-a", "Why do people dream?")
        )
        self.assertEqual(result.kind, "answer")
        self.assertEqual(context.requests, [])
        self.assertEqual(model.calls[1][1]["context"], {})

    def test_omnia_request_receives_only_policy_fields(self):
        model = FakeModel([
            {"category": "omnia", "policy": "study"},
            {"kind": "answer", "message": "You have one exam coming up.", "action": None},
        ])
        context = FakeContext({"exams": ["biology"], "nutrition": {"private": True}})
        result = OmniaAgent(model=model, context_provider=context).chat(
            AgentRequest("user-a", "What should I study next?")
        )
        self.assertEqual(result.kind, "answer")
        self.assertEqual(model.calls[1][1]["context"], {"exams": ["biology"]})
        self.assertEqual(context.requests, [("user-a", "study")])

    def test_missing_information_returns_clarification(self):
        model = FakeModel([
            {"category": "action", "policy": "task_action"},
            {"kind": "clarification", "message": "Which task should I move?", "action": None},
        ])
        result = OmniaAgent(model=model).chat(AgentRequest("user-a", "Move it to tomorrow"))
        self.assertTrue(result.needs_clarification)

    def test_action_proposal_is_stored_before_confirmation_is_offered(self):
        store = MemoryProposalStore()
        result = OmniaAgent(model=action_model(), proposal_store=store).chat(
            AgentRequest("user-a", "Add a study task")
        )
        self.assertTrue(result.needs_confirmation)
        self.assertIsNotNone(result.action)
        self.assertIn(result.action.proposal_id, store.proposals)

    def test_forged_confirmation_token_is_rejected(self):
        store = MemoryProposalStore()
        proposal = OmniaAgent(model=action_model(), proposal_store=store).chat(
            AgentRequest("user-a", "Add a study task")
        ).action
        executor = FakeExecutor()
        result = OmniaAgent(proposal_store=store, action_executor=executor).chat(
            AgentRequest("user-a", "Confirm", proposal.proposal_id, "forged")
        )
        self.assertEqual(result.error.category.value, "confirmation_rejected")
        self.assertEqual(executor.calls, [])

    def test_confirmation_cannot_supply_changed_arguments(self):
        with self.assertRaises(TypeError):
            AgentRequest("user-a", "Confirm", "proposal-1", "token", {"title": "tampered"})

    def test_model_argument_mutation_cannot_change_issued_proposal(self):
        source = {"kind": "action", "message": "Create", "action": {
            "name": "create_task", "arguments": {"title": "Original"}
        }}
        model = FakeModel([
            {"category": "action", "policy": "task_action"}, source,
        ])
        result = OmniaAgent(model=model, proposal_store=MemoryProposalStore()).chat(
            AgentRequest("user-a", "Create a task")
        )
        source["action"]["arguments"]["title"] = "Changed later"
        self.assertEqual(result.action.arguments["title"], "Original")
        with self.assertRaises(TypeError):
            result.action.arguments["title"] = "Changed by caller"

    def test_confirmation_uses_exact_persisted_arguments(self):
        store = MemoryProposalStore()
        proposal = OmniaAgent(model=action_model(), proposal_store=store).chat(
            AgentRequest("user-a", "Add a study task")
        ).action
        executor = FakeExecutor()
        result = OmniaAgent(proposal_store=store, action_executor=executor).chat(
            AgentRequest("user-a", "Confirm", proposal.proposal_id, store.token)
        )
        self.assertEqual(result.action_status, ExecutorStatus.SUCCESS)
        self.assertEqual(dict(executor.calls[0].proposal.arguments), {"title": "Revise biology"})
        self.assertEqual(executor.calls[0].idempotency_key, f"omnia-action:{proposal.proposal_id}")

    def test_confirmation_replay_is_rejected(self):
        store = MemoryProposalStore()
        proposal = OmniaAgent(model=action_model(), proposal_store=store).chat(
            AgentRequest("user-a", "Add a study task")
        ).action
        executor = FakeExecutor()
        agent = OmniaAgent(proposal_store=store, action_executor=executor)
        request = AgentRequest("user-a", "Confirm", proposal.proposal_id, store.token)
        self.assertEqual(agent.chat(request).action_status, ExecutorStatus.SUCCESS)
        self.assertEqual(agent.chat(request).error.category.value, "confirmation_rejected")
        self.assertEqual(len(executor.calls), 1)

    def test_cross_user_proposal_access_is_rejected(self):
        store = MemoryProposalStore()
        proposal = OmniaAgent(model=action_model(), proposal_store=store).chat(
            AgentRequest("user-a", "Add a study task")
        ).action
        executor = FakeExecutor()
        result = OmniaAgent(proposal_store=store, action_executor=executor).chat(
            AgentRequest("user-b", "Confirm", proposal.proposal_id, store.token)
        )
        self.assertEqual(result.error.category.value, "confirmation_rejected")
        self.assertEqual(executor.calls, [])

    def test_expired_proposal_is_rejected(self):
        store = MemoryProposalStore()
        proposal = ActionProposal("create_task", {"title": "Old"}, "expired", datetime.now(timezone.utc) - timedelta(seconds=1))
        store.store(user_id="user-a", proposal=proposal)
        executor = FakeExecutor()
        result = OmniaAgent(proposal_store=store, action_executor=executor).chat(
            AgentRequest("user-a", "Confirm", "expired", store.token)
        )
        self.assertEqual(result.error.category.value, "confirmation_rejected")

    def test_general_route_cannot_propose_action(self):
        model = FakeModel([
            {"category": "general", "policy": "general"},
            {"kind": "action", "message": "Create it", "action": {
                "name": "create_task", "arguments": {"title": "Task"}
            }},
        ])
        result = OmniaAgent(model=model, proposal_store=MemoryProposalStore()).chat(
            AgentRequest("user-a", "Tell me about task management")
        )
        self.assertEqual(result.error.category.value, "invalid_model_output")
        self.assertIsNone(result.action)

    def test_executor_denial_is_not_reported_as_success(self):
        store = MemoryProposalStore()
        proposal = OmniaAgent(model=action_model(), proposal_store=store).chat(
            AgentRequest("user-a", "Add task")
        ).action
        executor = FakeExecutor(ExecutorResult(ExecutorStatus.DENIED))
        result = OmniaAgent(proposal_store=store, action_executor=executor).chat(
            AgentRequest("user-a", "Confirm", proposal.proposal_id, store.token)
        )
        self.assertEqual(result.action_status, ExecutorStatus.DENIED)
        self.assertNotEqual(result.action_status, ExecutorStatus.SUCCESS)

    def test_executor_failure_and_ambiguous_post_commit_are_distinct(self):
        store = MemoryProposalStore()
        proposal = OmniaAgent(model=action_model(), proposal_store=store).chat(
            AgentRequest("user-a", "Add task")
        ).action
        failed = OmniaAgent(proposal_store=store, action_executor=FakeExecutor(
            ExecutorResult(ExecutorStatus.FAILED)
        )).chat(AgentRequest("user-a", "Confirm", proposal.proposal_id, store.token))
        self.assertEqual(failed.action_status, ExecutorStatus.FAILED)

        store2 = MemoryProposalStore()
        proposal2 = OmniaAgent(model=action_model(), proposal_store=store2).chat(
            AgentRequest("user-a", "Add task")
        ).action
        ambiguous = OmniaAgent(proposal_store=store2, action_executor=FakeExecutor(
            error=RuntimeError("secret db failure after commit")
        )).chat(AgentRequest("user-a", "Confirm", proposal2.proposal_id, store2.token))
        self.assertEqual(ambiguous.action_status, ExecutorStatus.AMBIGUOUS)
        self.assertNotIn("secret", ambiguous.message)

    def test_action_registry_is_immutable(self):
        from Gaoher.ai.agent.actions import ACTION_REGISTRY
        with self.assertRaises(TypeError):
            ACTION_REGISTRY["unsafe"] = ACTION_REGISTRY["create_task"]
        with self.assertRaises(TypeError):
            ACTION_REGISTRY["create_task"].required_arguments["other"] = str

    def test_unconfigured_model_and_proposal_store_are_explicit(self):
        result = OmniaAgent(model=PendingModelAdapter()).chat(AgentRequest("user-a", "Hi"))
        self.assertEqual(result.error.category.value, "model_pending")
        self.assertTrue(result.error.correlation_id)


if __name__ == "__main__":
    unittest.main()
