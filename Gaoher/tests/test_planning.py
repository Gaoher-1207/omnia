import unittest

from Gaoher.ai.planning.models import PlanStatus, PlanningRequest
from Gaoher.ai.planning.service import PlanningService
from Gaoher.ai.planning.validation import InvalidPlanningOutput


def session(title="Chapter 1", day="Today", duration=60, pause=None, priority="high", reason="Near deadline"):
    return {"title": title, "day": day, "duration_minutes": duration,
            "break_after_minutes": pause, "priority": priority, "reason": reason}


def output(sessions=None, status="proposed", assumptions=None, uncertainties=None, question=None):
    return {"status": status, "sessions": [session()] if sessions is None else sessions,
            "assumptions": ["Using the availability stated by the user"] if assumptions is None else assumptions,
            "uncertainties": [] if uncertainties is None else uncertainties,
            "clarification_question": question}


class Adapter:
    def __init__(self, response): self.response = response
    def generate_structured(self, task, payload, *, options):
        self.task, self.payload = task, payload
        return self.response


class PlanningTests(unittest.TestCase):
    def run_plan(self, response, text="I have 2 hours today, exam Friday", context=None, adaptation=False):
        adapter = Adapter(response)
        plan = PlanningService(adapter).create_plan(PlanningRequest(text, {} if context is None else context, adaptation))
        self.assertEqual(adapter.task, "create_plan")
        return plan, adapter

    def test_basic_study_plan(self):
        plan, _ = self.run_plan(output())
        self.assertEqual(plan.status, PlanStatus.PROPOSED)

    def test_multiple_subjects(self):
        plan, _ = self.run_plan(output([session("Biology", priority="high"), session("History", priority="medium")]))
        self.assertEqual(len(plan.sessions), 2)

    def test_exam_deadline(self):
        plan, _ = self.run_plan(output([session(day="Friday", reason="Exam Friday")]), "Exam Friday, 2 hours today")
        self.assertEqual(plan.sessions[0].day, "Friday")

    def test_limited_available_time(self):
        plan, _ = self.run_plan(output([session(duration=30)]), "I can study 30 minutes today")
        self.assertLessEqual(sum(s.duration_minutes for s in plan.sessions), 30)

    def test_existing_backlog(self):
        plan, adapter = self.run_plan(output([session("Finish overdue task")]), "Help plan", {"tasks": [{"title": "Finish overdue task", "status": "overdue"}]})
        self.assertIn("tasks", adapter.payload["authorized_context"])
        self.assertEqual(plan.sessions[0].title, "Finish overdue task")

    def test_missing_deadline_does_not_invent_one(self):
        plan, _ = self.run_plan(output([session(day=None)], assumptions=["No deadline was supplied"]), "Study 2 hours today")
        self.assertIsNone(plan.sessions[0].day)

    def test_missing_available_time_requests_clarification(self):
        plan, _ = self.run_plan(output([], status="clarification", assumptions=[], question="How much time is available?"), "Plan my study")
        self.assertEqual(plan.status, PlanStatus.CLARIFICATION)

    def test_conflicting_constraints(self):
        plan, _ = self.run_plan(output([], status="conflict", assumptions=[], question="The requested work exceeds available time."), "Exam tomorrow, 1 hour free", {"tasks": ["10 chapters"]})
        self.assertEqual(plan.status, PlanStatus.CONFLICT)

    def test_invalid_model_output(self):
        with self.assertRaises(InvalidPlanningOutput): self.run_plan({"status": "proposed"})

    def test_unrealistic_session_duration(self):
        with self.assertRaises(InvalidPlanningOutput): self.run_plan(output([session(duration=240)]))

    def test_empty_context(self):
        plan, adapter = self.run_plan(output(), context={})
        self.assertEqual(adapter.payload["authorized_context"], {})
        self.assertEqual(plan.status, PlanStatus.PROPOSED)

    def test_plan_adaptation(self):
        plan, adapter = self.run_plan(output([session("Remaining chapter", day="Tomorrow")]), "Adapt my plan", {"existing_plan": ["Missed Chapter 1"]}, True)
        self.assertTrue(adapter.payload["adaptation"])
        self.assertEqual(plan.sessions[0].title, "Remaining chapter")


if __name__ == "__main__": unittest.main()
