import uuid
from datetime import date, timedelta

from app.modules.study.planner import PlannerExam, PlannerItem, build_study_plan

START = date(2026, 3, 2)
PHY, MATH = uuid.uuid4(), uuid.uuid4()
SUBJECTS = {PHY: "Physics", MATH: "Maths"}


def item(subject, minutes, title="Topic", kind="backlog", order=0):
    return PlannerItem(id=uuid.uuid4(), subject_id=subject, title=title, kind=kind, minutes=minutes, order=order)


def exam(subject, days_from_start):
    return PlannerExam(
        id=uuid.uuid4(), subject_id=subject, title="Exam", exam_date=START + timedelta(days=days_from_start)
    )


def plan(**kwargs):
    defaults = dict(start=START, days=7, daily_minutes=120, studied_today=0, subjects=SUBJECTS, exams=[], items=[])
    defaults.update(kwargs)
    return build_study_plan(**defaults)


def test_never_exceeds_daily_goal_and_subtracts_todays_study():
    result = plan(items=[item(PHY, 600), item(MATH, 600)], studied_today=50)
    assert result.days[0].available_minutes == 70
    for day in result.days:
        assert day.planned_minutes <= day.available_minutes


def test_closer_exam_goes_first():
    result = plan(items=[item(MATH, 60, "Algebra"), item(PHY, 60, "Optics")], exams=[exam(PHY, 2), exam(MATH, 10)])
    assert result.days[0].blocks[0].title == "Optics"
    assert result.days[0].blocks[0].reason == "Exam in 2 days"


def test_subject_share_keeps_balance_when_both_have_work():
    result = plan(items=[item(PHY, 300), item(MATH, 300)], exams=[exam(PHY, 3)])
    day = result.days[0]
    per_subject = {}
    for block in day.blocks:
        per_subject[block.subject_name] = per_subject.get(block.subject_name, 0) + block.minutes
    assert per_subject["Physics"] == 72
    assert per_subject["Maths"] == 48


def test_single_subject_can_use_whole_day():
    result = plan(items=[item(PHY, 500)])
    assert result.days[0].planned_minutes == 120


def test_exam_day_is_light_review_only():
    result = plan(items=[item(PHY, 500)], exams=[exam(PHY, 0)])
    today = result.days[0]
    assert sum(b.minutes for b in today.blocks if b.subject_name == "Physics") <= 45
    assert today.blocks[0].reason == "Exam today — light review"
    assert today.exams[0].subject_name == "Physics"


def test_warns_when_backlog_cannot_fit_before_exam():
    result = plan(items=[item(PHY, 600)], exams=[exam(PHY, 2)], daily_minutes=60)
    assert result.warnings and "Physics" in result.warnings[0]


def test_general_revision_fills_spare_time_before_exams():
    result = plan(items=[], exams=[exam(MATH, 5)])
    first = result.days[0].blocks
    assert first and first[0].title == "General revision" and first[0].backlog_item_id is None


def test_past_exams_and_unknown_subjects_ignored():
    stranger = uuid.uuid4()
    result = plan(items=[item(stranger, 60)], exams=[exam(PHY, -1)])
    assert all(not d.blocks for d in result.days)
    assert result.unscheduled_minutes == 0


def test_zero_goal_warns():
    result = plan(daily_minutes=0, items=[item(PHY, 60)])
    assert result.unscheduled_minutes == 60
    assert "0 minutes" in result.warnings[0]


def test_item_split_across_days():
    result = plan(items=[item(PHY, 200, "Big chapter")], daily_minutes=120)
    assert result.days[0].blocks[0].minutes == 120
    assert result.days[1].blocks[0].minutes == 80
