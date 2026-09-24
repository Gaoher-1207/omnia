"""Offline end-to-end evaluation through the central Agent."""

from dataclasses import dataclass
import json
import time
from typing import Any, Mapping, Sequence

from Gaoher.ai.agent.agent import OmniaAgent
from Gaoher.ai.agent.model_adapter import ProviderFailure, ProviderTimeout, ProviderUnavailable
from Gaoher.ai.agent.models import AgentRequest
from Gaoher.ai.context.context_manager import CONTEXT_POLICIES
from Gaoher.ai.integrations.confirmation_store import ProposalStoreResult, ProposalStoreStatus
from .models import EvaluationReport, EvaluationScenario, ScenarioResult
from .scenarios import SCENARIOS, default_module_output
from .validation import InvalidScenario, validate_scenario


_TASKS = {"planning": "create_plan", "recommendation": "recommend", "progress": "analyze_progress",
          "goals_streaks": "analyze_goals_streaks", "nutrition": "analyze_nutrition", "coaching": "coach"}


class _ContextProvider:
    def __init__(self, scenario: EvaluationScenario):
        self.scenario = scenario
        self.calls: list[tuple[str, str]] = []

    def get_context(self, *, user_id: str, policy: str) -> Mapping[str, Any]:
        self.calls.append((user_id, policy))
        if user_id != self.scenario.user_id:
            return {}
        return self.scenario.authorized_context


class _ProposalStore:
    def store(self, *, user_id, proposal):
        return ProposalStoreResult(ProposalStoreStatus.STORED)

    def claim(self, *, user_id, proposal_id, confirmation_token, now):
        return ProposalStoreResult(ProposalStoreStatus.REJECTED)


class _NoExecution:
    def __init__(self):
        self.calls = 0

    def execute(self, *, action):
        self.calls += 1
        raise AssertionError("evaluation must not execute actions")


class _DeterministicAdapter:
    """ModelAdapter fake that selects only the current scenario's fixed output."""
    def __init__(self, scenario: EvaluationScenario):
        self.scenario = scenario
        self.calls: list[tuple[str, Mapping[str, Any]]] = []

    def generate_structured(self, task, payload, *, options):
        self.calls.append((task, payload))
        behavior = self.scenario.model_behavior
        if behavior == "provider_timeout":
            raise ProviderTimeout("simulated provider timeout; private detail")
        if behavior == "provider_error":
            raise ProviderUnavailable("simulated provider failure; private detail")
        if behavior == "invalid_route" and task == "route_request":
            return {"category": "not-authorized", "policy": "food", "intent": "recommendation", "use_memory": False}
        if task == "route_request":
            return dict(self.scenario.expected_route)
        if behavior == "empty_result":
            return {}
        if behavior == "malformed_result":
            return "not an object"
        if behavior == "oversized_result":
            return {"status": "ready", "message": "x" * 9000}
        if task in _TASKS.values() or task == "respond":
            return self.scenario.module_output if self.scenario.module_output is not None else default_module_output(self.scenario.expected_route["intent"])
        raise ProviderFailure("unexpected model task")


class EvaluationRunner:
    """Run validated scenarios, returning metadata-only and sanitized reports."""

    def run(self, scenarios: Sequence[EvaluationScenario] = SCENARIOS) -> EvaluationReport:
        results = tuple(self.run_scenario(s) for s in scenarios)
        passed = sum(result.passed for result in results)
        failed = len(results) - passed
        return EvaluationReport(len(results), passed, failed, 0, results)

    def run_scenario(self, scenario: EvaluationScenario) -> ScenarioResult:
        started = time.perf_counter()
        try:
            validate_scenario(scenario)
        except InvalidScenario:
            return ScenarioResult(getattr(scenario, "scenario_id", "invalid"), getattr(scenario, "category", "invalid"), False,
                                  "invalid scenario definition", _elapsed(started))

        model = _DeterministicAdapter(scenario)
        context = _ContextProvider(scenario)
        executor = _NoExecution()
        try:
            agent = OmniaAgent(model=model, context_provider=context, action_executor=executor, proposal_store=_ProposalStore())
            response = agent.chat(AgentRequest(scenario.user_id, scenario.user_request), memory_request=scenario.memory)
            reason = self._assertions(scenario, response, model, context, executor)
        except Exception:
            # Never serialize arbitrary provider, prompt, context, or traceback text.
            reason = "evaluation execution failed safely"
        return ScenarioResult(scenario.scenario_id, scenario.category, reason is None, reason, _elapsed(started))

    @staticmethod
    def _assertions(scenario, response, model, context, executor):
        if response.status != scenario.expected_result_status:
            return "unexpected result status"
        if response.error and not response.correlation_id:
            return "failure response omitted correlation ID"
        intent = scenario.expected_route["intent"]
        if intent != "clarification" and response.status != "error" and response.intent != intent:
            return "unexpected route intent"
        expected_calls = [] if intent in {"general", "clarification"} or (response.status == "error" and not context.calls) else [(scenario.user_id, scenario.expected_context_policy)]
        if context.calls != expected_calls:
            return "context policy or user scope mismatch"
        module_calls = [task for task, _ in model.calls if task in set(_TASKS.values())]
        expected_task = _TASKS.get(intent)
        if expected_task and response.status != "error" and module_calls != [expected_task]:
            return "expected module was not called exactly once"
        if not expected_task and module_calls:
            return "unexpected AI module invocation"
        if intent == "action":
            if not response.needs_confirmation or response.action is None:
                return "action proposal did not require confirmation"
        if "direct_action_execution" in scenario.forbidden_behavior and executor.calls:
            return "privileged action was executed"
        if "user_identity_in_payload" in scenario.forbidden_behavior:
            if any(_contains_key(payload, "user_id") for _, payload in model.calls):
                return "user identity entered model payload"
        if "unrelated_context" in scenario.forbidden_behavior:
            allowed = set(CONTEXT_POLICIES.get(scenario.expected_context_policy, ()))
            for _, payload in model.calls:
                context_value = payload.get("context", {})
                if isinstance(context_value, Mapping) and set(context_value) - allowed:
                    return "unrelated context entered model payload"
        if "unrelated_memory" in scenario.forbidden_behavior:
            text = json.dumps([payload for _, payload in model.calls], default=str).casefold()
            if "vegetarian dinner preferences" in text:
                return "unrelated memory entered model payload"
        # Sensitive fixture text must never be reflected to the caller or report.
        if "should-never-be-shown" in response.message:
            return "sensitive content reached user response"
        return None


def _contains_key(value, key):
    if isinstance(value, Mapping):
        return key in value or any(_contains_key(item, key) for item in value.values())
    if isinstance(value, (tuple, list)):
        return any(_contains_key(item, key) for item in value)
    return False


def _elapsed(started):
    return round((time.perf_counter() - started) * 1000, 3)
