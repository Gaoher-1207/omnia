import unittest

from Gaoher.ai.agent.validation import InvalidContext
from Gaoher.ai.context.context_manager import AuthorizedContext, ContextManager
from Gaoher.ai.progress.models import ProgressRequest, ProgressStatus, ProgressTrend
from Gaoher.ai.progress.service import ProgressService
from Gaoher.ai.progress.validation import InvalidProgressOutput


def metric(name="tasks", completed=8, total=10, rate=None):
    return {"name": name, "completed": completed, "total": total, "completion_rate": rate}


def area(domain="productivity", trend="insufficient_data", metrics=None):
    return {"domain": domain, "summary": "Task completion for this period.", "metrics": [metric()] if metrics is None else metrics, "trend": trend}


def output(status="ready", metrics=None, areas=None, trends=None, summary=None, **overrides):
    value = {"status": status, "summary": {"fact": "Completed 8 of 10 planned tasks.", "interpretation": "Most planned tasks were completed."} if summary is None and status == "ready" else summary,
        "completed_items": ["Read chapter 1"], "metrics": [metric()] if metrics is None else metrics,
        "areas": [area()] if areas is None else areas, "strengths": ["Consistent study sessions"],
        "attention_areas": ["Two tasks remain"], "trends": ["insufficient_data"] if trends is None else trends,
        "blockers": ["Limited time"], "suggested_next_focus": "Complete the next priority task.",
        "confidence": "medium", "uncertainty": "Only current-period data was supplied.", "clarification_question": None}
    if status != "ready":
        value.update(summary=None, completed_items=[], metrics=[], areas=[], strengths=[], attention_areas=[], trends=[], blockers=[], suggested_next_focus=None, clarification_question="Which period should I review?")
    value.update(overrides)
    return value


class Adapter:
    def __init__(self, response): self.response = response
    def generate_structured(self, task, payload, *, options):
        self.task, self.payload = task, payload
        return self.response


def selected(values, policy="progress", category="omnia"):
    return ContextManager().select_for_user(AuthorizedContext("alice", values), user_id="alice", category=category, policy=policy)


class ProgressTests(unittest.TestCase):
    def analyze(self, response=None, context=None, text="How did I perform this week?", user="alice", policy="progress"):
        adapter = Adapter(output() if response is None else response)
        result = ProgressService(adapter).analyze(ProgressRequest(user, text, selected({} if context is None else context, policy=policy)))
        self.assertEqual(adapter.task, "analyze_progress")
        self.assertNotIn("user_id", adapter.payload)
        return result, adapter

    def test_basic_progress_analysis(self):
        result, _ = self.analyze()
        self.assertEqual(result.status, ProgressStatus.READY)

    def test_study_progress(self):
        result, _ = self.analyze(output(areas=[area("study")]), {"study_progress": {"chapters_completed": 2}})
        self.assertEqual(result.areas[0].domain, "study")

    def test_productivity_progress(self):
        result, _ = self.analyze(context={"tasks": [{"status": "completed"}]})
        self.assertEqual(result.areas[0].domain, "productivity")

    def test_fitness_progress(self):
        result, _ = self.analyze(output(areas=[area("fitness")]), {"activity": [{"steps": 5000}]}, policy="fitness")
        self.assertEqual(result.areas[0].domain, "fitness")

    def test_nutrition_progress(self):
        result, _ = self.analyze(output(areas=[area("nutrition")]), {"nutrition": {"meals_logged": 2}}, policy="food")
        self.assertEqual(result.areas[0].domain, "nutrition")

    def test_goal_progress(self):
        result, _ = self.analyze(output(areas=[area("goals")]), {"goals": [{"name": "Read"}]})
        self.assertEqual(result.areas[0].domain, "goals")

    def test_completed_total_metrics(self):
        result, _ = self.analyze()
        self.assertEqual((result.metrics[0].completed, result.metrics[0].total), (8, 10))

    def test_completion_rate_calculated_from_counts(self):
        result, _ = self.analyze(output(metrics=[metric()]))
        self.assertEqual(result.metrics[0].completion_rate, .8)

    def test_missing_total_has_no_rate(self):
        result, _ = self.analyze(output(metrics=[metric(total=None)]))
        self.assertIsNone(result.metrics[0].completion_rate)

    def test_missing_completed_has_no_rate(self):
        result, _ = self.analyze(output(metrics=[metric(completed=None)]))
        self.assertIsNone(result.metrics[0].completion_rate)

    def test_insufficient_context_result(self):
        result, _ = self.analyze(output(status="insufficient_context"), {})
        self.assertEqual(result.status, ProgressStatus.INSUFFICIENT_CONTEXT)

    def test_empty_context_is_valid_input(self):
        result, adapter = self.analyze(output(status="clarification"), {})
        self.assertEqual(adapter.payload["authorized_selected_context"], {})
        self.assertEqual(result.status, ProgressStatus.CLARIFICATION)

    def test_trend_with_comparable_periods(self):
        result, _ = self.analyze(output(areas=[area(trend="improving")], trends=["improving"]), {"study_progress": {"weekly_history": [{"completed": 4}, {"completed": 8}]}})
        self.assertEqual(result.trends[0], ProgressTrend.IMPROVING)

    def test_trend_without_comparable_periods_rejected(self):
        with self.assertRaises(InvalidProgressOutput): self.analyze(output(areas=[area(trend="improving")], trends=["improving"]), {"tasks": []})

    def test_improving_trend(self):
        result, _ = self.analyze(output(trends=["improving"]), {"study_progress": {"weekly_history": [1, 2]}})
        self.assertEqual(result.trends[0], ProgressTrend.IMPROVING)

    def test_stable_trend(self):
        result, _ = self.analyze(output(trends=["stable"]), {"study_progress": {"weekly_history": [2, 2]}})
        self.assertEqual(result.trends[0], ProgressTrend.STABLE)

    def test_declining_trend(self):
        result, _ = self.analyze(output(trends=["declining"]), {"study_progress": {"weekly_history": [8, 3]}})
        self.assertEqual(result.trends[0], ProgressTrend.DECLINING)

    def test_no_invented_metrics(self):
        result, _ = self.analyze(output(metrics=[]), {})
        self.assertEqual(result.metrics, ())

    def test_no_unsupported_trend(self):
        with self.assertRaises(InvalidProgressOutput): self.analyze(output(trends=["improving"]), {})

    def test_strength_identification(self):
        result, _ = self.analyze()
        self.assertEqual(result.strengths, ("Consistent study sessions",))

    def test_area_needing_attention(self):
        result, _ = self.analyze()
        self.assertEqual(result.attention_areas, ("Two tasks remain",))

    def test_blockers_and_suggested_focus(self):
        result, _ = self.analyze()
        self.assertEqual(result.blockers, ("Limited time",))
        self.assertTrue(result.suggested_next_focus)

    def test_invalid_model_output(self):
        with self.assertRaises(InvalidProgressOutput): self.analyze({"status": "ready"})

    def test_invalid_metric_values(self):
        for bad in (metric(completed=-1), metric(completed=11), metric(rate=1.2), metric(rate=.4)):
            with self.subTest(bad=bad), self.assertRaises(InvalidProgressOutput): self.analyze(output(metrics=[bad]))

    def test_invalid_confidence(self):
        with self.assertRaises(InvalidProgressOutput): self.analyze(output(confidence="certain"))

    def test_unsupported_fields(self):
        bad = output(); bad["user_id"] = "private"
        with self.assertRaises(InvalidProgressOutput): self.analyze(bad)

    def test_sensitive_internal_information_excluded(self):
        with self.assertRaises(InvalidProgressOutput): self.analyze(output(summary={"fact": "API_KEY abc", "interpretation": None}))

    def test_user_context_isolation(self):
        ctx = ContextManager().select_for_user(AuthorizedContext("alice", {"study_progress": {"chapters": 2}}), user_id="alice", category="omnia", policy="study")
        with self.assertRaises(InvalidContext):
            ProgressService(Adapter(output())).analyze(ProgressRequest("bob", "Progress?", ctx))

    def test_provider_neutral_adapter(self):
        _, adapter = self.analyze()
        self.assertEqual(adapter.task, "analyze_progress")

    def test_progress_service_only_returns_analysis_never_executes_actions(self):
        result, _ = self.analyze()
        self.assertFalse(hasattr(result, "action"))
        self.assertFalse(hasattr(result, "execute"))


if __name__ == "__main__": unittest.main()
