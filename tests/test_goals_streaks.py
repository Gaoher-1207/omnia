import unittest

from Gaoher.ai.agent.validation import InvalidContext
from Gaoher.ai.context.context_manager import AuthorizedContext, ContextManager
from Gaoher.ai.goals_streaks.models import GoalsStreaksRequest, GoalsStreaksStatus, GoalStatus, StreakStatus
from Gaoher.ai.goals_streaks.service import GoalsStreaksService
from Gaoher.ai.goals_streaks.validation import InvalidGoalsStreaksOutput


def goal(reference="g1", title="Study Python", status="active", current=6, target=10, deadline=None, priority="high", domain="study", assessment="insufficient_information"):
    progress = current / target if current is not None and target not in (None, 0) else None
    return {"reference": reference, "title": title, "domain": domain, "status": status,
            "current_value": current, "target": target, "progress": progress,
            "deadline": deadline, "priority": priority, "deadline_assessment": assessment}


def streak(domain="study", kind="daily", current=4, longest=9, status="active", last="2026-09-23"):
    return {"domain": domain, "streak_type": kind, "current_streak": current,
            "longest_streak": longest, "status": status, "last_activity": last}


def response(goals=None, streaks=None, status="ready", **overrides):
    if status == "ready":
        goals = [goal()] if goals is None else goals
        streaks = [streak()] if streaks is None else streaks
        active = [g["reference"] for g in goals if g["status"] == "active"]
        completed = [g["reference"] for g in goals if g["status"] == "completed"]
        attention = [g["reference"] for g in goals if g["status"] in {"active", "paused", "missed", "unknown"}]
        result = {"status": status, "goal_summary": "One active goal is progressing.", "goals": goals,
            "active_goals": active, "completed_goals": completed, "goals_needing_attention": attention,
            "streak_summary": "One active streak is recorded.", "streaks": streaks, "streak_insights": ["The study streak is active."],
            "goal_insights": [{"text": "Continue steady progress.", "related_goal": "g1" if goals else None, "kind": "strength"}],
            "goal_conflicts": [], "suggested_next_focus": "Continue the next study session.", "confidence": "medium",
            "uncertainty": None, "clarification_question": None}
    else:
        result = {"status": status, "goal_summary": None, "goals": [], "active_goals": [], "completed_goals": [],
            "goals_needing_attention": [], "streak_summary": None, "streaks": [], "streak_insights": [],
            "goal_insights": [],
            "goal_conflicts": [], "suggested_next_focus": None, "confidence": "low",
            "uncertainty": "No selected goal or streak data.", "clarification_question": "Which goal or streak should I review?"}
    result.update(overrides)
    return result


class Adapter:
    def __init__(self, result): self.result = result
    def generate_structured(self, task, payload, *, options):
        self.task, self.payload = task, payload
        return self.result


def selected(values, user="alice"):
    return ContextManager().select_for_user(AuthorizedContext(user, values), user_id=user, category="omnia", policy="goals")


class GoalsStreaksTests(unittest.TestCase):
    def analyze(self, output=None, context=None, user="alice"):
        source = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "target": 10, "priority": "high"}],
                  "streaks": [{"domain": "study", "streak_type": "daily", "current_streak": 4, "longest_streak": 9, "status": "active", "last_activity": "2026-09-23"}]}
        if context is not None: source = context
        adapter = Adapter(response() if output is None else output)
        result = GoalsStreaksService(adapter).analyze(GoalsStreaksRequest(user, "Review my goals and streaks", selected(source),))
        self.assertEqual(adapter.task, "analyze_goals_streaks")
        self.assertNotIn("user_id", adapter.payload)
        return result, adapter

    def test_basic_goal_analysis(self):
        result, _ = self.analyze()
        self.assertEqual(result.status, GoalsStreaksStatus.READY)

    def test_active_goals(self):
        result, _ = self.analyze()
        self.assertEqual(result.active_goals, ("g1",))

    def test_completed_goals(self):
        source = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "completed", "current_value": 10, "target": 10, "priority": "high"}], "streaks": [{"domain": "study", "streak_type": "daily", "current_streak": 4, "longest_streak": 9, "status": "active", "last_activity": "2026-09-23"}]}
        result, _ = self.analyze(response([goal(status="completed", current=10)]), source)
        self.assertEqual(result.completed_goals, ("g1",))
        self.assertEqual(result.goals[0].status, GoalStatus.COMPLETED)

    def test_missed_goals(self):
        source = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "missed", "current_value": 6, "target": 10, "priority": "high"}], "streaks": []}
        result, _ = self.analyze(response([goal(status="missed")], []), source)
        self.assertEqual(result.goals_needing_attention, ("g1",))

    def test_paused_goals(self):
        source = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "paused", "current_value": 6, "target": 10, "priority": "high"}], "streaks": []}
        result, _ = self.analyze(response([goal(status="paused")], []), source)
        self.assertEqual(result.goals[0].status, GoalStatus.PAUSED)

    def test_goal_progress_calculation(self):
        result, _ = self.analyze()
        self.assertAlmostEqual(result.goals[0].progress.progress, .6)

    def test_missing_target_has_no_progress(self):
        result, _ = self.analyze(response([goal(target=None, assessment="insufficient_information")], []), {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "priority": "high"}]})
        self.assertIsNone(result.goals[0].progress.progress)

    def test_missing_current_has_no_progress(self):
        result, _ = self.analyze(response([goal(current=None, assessment="insufficient_information")], []), {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "target": 10, "priority": "high"}]})
        self.assertIsNone(result.goals[0].progress.progress)

    def test_invalid_progress_rejected(self):
        bad = response(); bad["goals"][0]["progress"] = 1.5
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze(bad)

    def test_deadline_handling_without_time_reference(self):
        src = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "target": 10, "deadline": "2026-10-02", "priority": "high"}]}
        result, _ = self.analyze(response([goal(deadline="2026-10-02")], []), src)
        self.assertEqual(result.goals[0].deadline_assessment.value, "insufficient_information")

    def test_overdue_goal(self):
        src = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "target": 10, "deadline": "2026-09-20", "priority": "high"}], "time_context": {"current_date": "2026-09-24"}}
        result, _ = self.analyze(response([goal(deadline="2026-09-20", assessment="overdue")], []), src)
        self.assertEqual(result.goals[0].deadline_assessment.value, "overdue")

    def test_approaching_deadline(self):
        src = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "target": 10, "deadline": "2026-09-26", "priority": "high"}], "time_context": {"current_date": "2026-09-24"}}
        result, _ = self.analyze(response([goal(deadline="2026-09-26", assessment="approaching")], []), src)
        self.assertEqual(result.goals[0].deadline_assessment.value, "approaching")

    def test_basic_streak_analysis(self):
        result, _ = self.analyze()
        self.assertEqual(len(result.streaks), 1)

    def test_active_streak(self):
        result, _ = self.analyze()
        self.assertEqual(result.streaks[0].status, StreakStatus.ACTIVE)

    def test_broken_streak_only_when_context_supports(self):
        src = {"goals": [], "streaks": [{"domain": "study", "streak_type": "daily", "current_streak": 0, "longest_streak": 9, "status": "broken", "last_activity": "2026-09-20"}]}
        result, _ = self.analyze(response([], [streak(current=0, status="broken", last="2026-09-20")]), src)
        self.assertEqual(result.streaks[0].status, StreakStatus.BROKEN)

    def test_longest_streak(self):
        result, _ = self.analyze(response([], [streak(status="longest")]), {"goals": [], "streaks": [{"domain": "study", "streak_type": "daily", "current_streak": 4, "longest_streak": 9, "status": "longest", "last_activity": "2026-09-23"}]})
        self.assertEqual(result.streaks[0].longest_streak, 9)

    def test_streak_at_risk(self):
        result, _ = self.analyze(response([], [streak(status="at_risk")]), {"goals": [], "streaks": [{"domain": "study", "streak_type": "daily", "current_streak": 4, "longest_streak": 9, "status": "at_risk", "last_activity": "2026-09-23"}]})
        self.assertEqual(result.streaks[0].status, StreakStatus.AT_RISK)

    def test_insufficient_streak_data(self):
        result, _ = self.analyze(response([], [streak(current=None, longest=None, status="insufficient_data", last=None)]), {"goals": [], "streaks": [{"domain": "study", "streak_type": "daily", "status": "insufficient_data"}]})
        self.assertEqual(result.streaks[0].status, StreakStatus.INSUFFICIENT_DATA)

    def test_no_invented_goal_values(self):
        bad = response(); bad["goals"][0]["target"] = 12; bad["goals"][0]["progress"] = .5
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze(bad)

    def test_no_invented_streak_values(self):
        bad = response(); bad["streaks"][0]["current_streak"] = 99
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze(bad)

    def test_goal_conflict_requires_context_evidence(self):
        g1 = goal(); g2 = goal("g2", "Exercise", domain="fitness")
        bad = response([g1, g2], [])
        bad["goal_conflicts"] = [{"goal_references": ["g1", "g2"], "shared_constraint": "time", "explanation": "Both require the same hour."}]
        src = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "target": 10, "priority": "high"}, {"reference": "g2", "title": "Exercise", "domain": "fitness", "status": "active", "current_value": 6, "target": 10, "priority": "high"}]}
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze(bad, src)

    def test_goal_conflict_with_explicit_shared_constraint(self):
        g1, g2 = goal(), goal("g2", "Exercise", domain="fitness")
        conflict = {"goal_references": ["g1", "g2"], "shared_constraint": "evening_time", "explanation": "Both goals use the same evening time window."}
        src = {"goals": {"items": [
            {"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "target": 10, "priority": "high"},
            {"reference": "g2", "title": "Exercise", "domain": "fitness", "status": "active", "current_value": 6, "target": 10, "priority": "high"}], "conflicts": [conflict]}}
        result, _ = self.analyze(response([g1, g2], [], goal_conflicts=[conflict]), src)
        self.assertEqual(result.goal_conflicts[0].goal_references, ("g1", "g2"))

    def test_suggested_next_focus(self):
        result, _ = self.analyze()
        self.assertTrue(result.suggested_next_focus)

    def test_confidence_validation(self):
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze(response(confidence="certain"))

    def test_invalid_model_output(self):
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze({"status": "ready"})

    def test_unsupported_fields(self):
        bad = response(); bad["internal_prompt"] = "do not reveal"
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze(bad)

    def test_sensitive_internal_information_exclusion(self):
        with self.assertRaises(InvalidGoalsStreaksOutput): self.analyze(response(goal_summary="API_KEY exposed"))

    def test_user_context_isolation(self):
        selected_ctx = selected({"goals": []}, user="alice")
        with self.assertRaises(InvalidContext):
            GoalsStreaksService(Adapter(response())).analyze(GoalsStreaksRequest("bob", "Review goals", selected_ctx))

    def test_provider_neutral_behavior(self):
        _, adapter = self.analyze()
        self.assertEqual(adapter.task, "analyze_goals_streaks")

    def test_service_cannot_execute_actions(self):
        result, _ = self.analyze()
        self.assertFalse(hasattr(result, "execute"))
        self.assertFalse(hasattr(result, "action"))

    def test_empty_context(self):
        result, _ = self.analyze(response(status="insufficient_context"), {})
        self.assertEqual(result.status, GoalsStreaksStatus.INSUFFICIENT_CONTEXT)

    def test_insufficient_context(self):
        result, _ = self.analyze(response(status="clarification"), {})
        self.assertEqual(result.status, GoalsStreaksStatus.CLARIFICATION)

    def test_multiple_goals(self):
        goals = [goal(), goal("g2", "Read weekly", status="completed", current=10)]
        source = {"goals": [{"reference": "g1", "title": "Study Python", "domain": "study", "status": "active", "current_value": 6, "target": 10, "priority": "high"}, {"reference": "g2", "title": "Read weekly", "domain": "study", "status": "completed", "current_value": 10, "target": 10, "priority": "high"}]}
        result, _ = self.analyze(response(goals, []), source)
        self.assertEqual(len(result.goals), 2)

    def test_multiple_streaks(self):
        ss = [streak(), streak("fitness", "weekly", 2, 5, "active", "2026-09-22")]
        source = {"goals": [], "streaks": [{"domain": "study", "streak_type": "daily", "current_streak": 4, "longest_streak": 9, "status": "active", "last_activity": "2026-09-23"}, {"domain": "fitness", "streak_type": "weekly", "current_streak": 2, "longest_streak": 5, "status": "active", "last_activity": "2026-09-22"}]}
        result, _ = self.analyze(response([], ss), source)
        self.assertEqual(len(result.streaks), 2)


if __name__ == "__main__": unittest.main()
