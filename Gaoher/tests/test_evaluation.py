"""Deterministic integration coverage for the full OMNIA AI stack."""
from dataclasses import replace
import unittest

from Gaoher.ai.evaluation.models import EvaluationReport
from Gaoher.ai.evaluation.runner import EvaluationRunner
from Gaoher.ai.evaluation.scenarios import SCENARIOS
from Gaoher.ai.evaluation.validation import InvalidScenario, validate_scenario


class EvaluationTests(unittest.TestCase):
    def test_all_curated_end_to_end_scenarios_pass(self):
        report = EvaluationRunner().run()
        self.assertIsInstance(report, EvaluationReport)
        self.assertEqual(report.total_scenarios, 20)
        self.assertEqual((report.passed, report.failed, report.skipped), (20, 0, 0))
        self.assertTrue(all(result.execution_time_ms >= 0 for result in report.results))

    def test_scenario_definitions_are_valid(self):
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario.scenario_id):
                self.assertIs(validate_scenario(scenario), scenario)

    def test_invalid_scenarios_are_rejected_and_cannot_pass(self):
        invalid_definitions = [
            {"expected_route": {"category": "invalid", "policy": "x", "intent": "planning", "use_memory": False}},
            {"expected_context_policy": "food"}, {"category": "unknown"},
            {"user_request": "x" * 4001}, {"model_behavior": "invented_behavior"}, {"expected_module": "nutrition"},
        ]
        for change in invalid_definitions:
            with self.subTest(change=change):
                invalid = replace(SCENARIOS[0], **change)
                with self.assertRaises(InvalidScenario):
                    validate_scenario(invalid)
                result = EvaluationRunner().run_scenario(invalid)
                self.assertFalse(result.passed)
                self.assertEqual(result.failure_reason, "invalid scenario definition")

    def test_report_contains_only_scenario_metadata_and_safe_failure_reason(self):
        scenario = replace(SCENARIOS[0], model_behavior="provider_timeout")
        report = EvaluationRunner().run([scenario])
        self.assertEqual(report.failed, 1)
        result = report.results[0]
        self.assertEqual((result.scenario_id, result.category), (scenario.scenario_id, scenario.category))
        self.assertEqual(result.failure_reason, "unexpected result status")
        self.assertNotIn("private detail", repr(report))
        self.assertNotIn(scenario.user_request, repr(report))

    def test_failed_assertion_is_reported_without_input_or_provider_data(self):
        scenario = replace(SCENARIOS[0], expected_result_status="error")
        report = EvaluationRunner().run([scenario])
        self.assertEqual(report.failed, 1)
        self.assertEqual(report.results[0].failure_reason, "unexpected result status")
        self.assertNotIn(scenario.user_request, repr(report))

    def test_provider_and_structured_output_failures_are_safe_and_correlated(self):
        for behavior in ("provider_error", "empty_result", "malformed_result", "oversized_result"):
            with self.subTest(behavior=behavior):
                scenario = replace(SCENARIOS[1], model_behavior=behavior, expected_result_status="error")
                report = EvaluationRunner().run([scenario])
                self.assertEqual((report.passed, report.failed), (1, 0))
                self.assertNotIn("private detail", repr(report))

    def test_no_direct_action_execution_and_confirmation_boundary(self):
        result = EvaluationRunner().run([next(item for item in SCENARIOS if item.scenario_id == "action-proposal")])
        self.assertEqual((result.passed, result.failed), (1, 0))

    def test_user_contexts_are_request_scoped_in_both_directions(self):
        from Gaoher.ai.evaluation.runner import _ContextProvider, _DeterministicAdapter
        from Gaoher.ai.agent.agent import OmniaAgent
        from Gaoher.ai.agent.models import AgentRequest

        first = replace(SCENARIOS[14], user_id="user-A", authorized_context={"tasks": [{"title": "A-only-marker"}]})
        second = replace(SCENARIOS[14], scenario_id="user-b-isolation", user_id="user-B",
                         authorized_context={"tasks": [{"title": "B-only-marker"}]})
        observations = []
        for own, forbidden in ((first, "B-only-marker"), (second, "A-only-marker")):
            adapter = _DeterministicAdapter(own)
            provider = _ContextProvider(own)
            agent = OmniaAgent(model=adapter, context_provider=provider)
            response = agent.chat(AgentRequest(own.user_id, own.user_request))
            self.assertEqual(response.status, "ready")
            payload = repr(adapter.calls)
            self.assertIn(own.authorized_context["tasks"][0]["title"], payload)
            self.assertNotIn(forbidden, payload)
            self.assertTrue(all(not _has_user_id(payload_item) for _, payload_item in adapter.calls))
            observations.append(provider.calls)
        self.assertEqual(observations, [[("user-A", "productivity")], [("user-B", "productivity")]])


def _has_user_id(value):
    from collections.abc import Mapping
    if isinstance(value, Mapping):
        return "user_id" in value or any(_has_user_id(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return any(_has_user_id(item) for item in value)
    return False
