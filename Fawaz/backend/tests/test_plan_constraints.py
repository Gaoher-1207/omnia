from datetime import UTC, datetime

import pytest

from app.modules.ai.schemas import AIPlanContent
from app.modules.ai.service import get_provider


@pytest.fixture(autouse=True)
def evening(monkeypatch):
    monkeypatch.setattr("app.core.time.utcnow", lambda: datetime(2026, 9, 27, 19, tzinfo=UTC))


def task(client, headers, **fields):
    return client.post("/api/tasks", headers=headers, json={"title": "Assignment", **fields}).json()


def test_deadline_estimate_and_unplaced_work_survive_persistence(client, headers):
    urgent = task(client, headers, due_date="2026-09-27", due_time="20:00", estimated_minutes=55)
    impossible = task(client, headers, title="Large project", estimated_minutes=240)
    result = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert result.status_code == 201
    plan = result.json()
    first = plan["items"][0]
    assert (first["task_id"], first["start"], first["end"]) == (urgent["id"], "19:00", "19:55")
    assert any(i["task_id"] == impossible["id"] and i["remaining_minutes"] == 240 for i in plan["unscheduled"])
    assert plan["window_end"] == "22:00" and plan["validation_version"] == 1
    assert client.get("/api/ai/daily-plan", headers=headers).json() == plan


@pytest.mark.parametrize(
    "changes",
    [
        {"task_ref": "t999"},
        {"task_ref": None},
        {"start": "18:00", "end": "18:30"},
        {"end": "20:30"},
        {"end": "19:10"},
        {"category": "study", "study_ref": "b999"},
    ],
)
def test_invalid_provider_candidates_fall_back_without_storing_fabrications(app, client, headers, changes):
    task(client, headers, estimated_minutes=30, due_date="2026-09-27", due_time="20:00")

    class Invalid:
        name = "external"

        def generate(self, context):
            assert context.open_tasks[0].due_time == "20:00"
            assert context.open_tasks[0].estimated_minutes == 30
            return AIPlanContent(
                summary="Fabrication",
                items=[
                    {
                        "start": "19:00",
                        "end": "19:30",
                        "category": "task",
                        "title": "Fabricated title",
                        "task_ref": "t1",
                        **changes,
                    }
                ],
            )

    app.dependency_overrides[get_provider] = Invalid
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["is_fallback"] is True and plan["source"] == "rules"
    assert "Fabricat" not in str(plan)


def test_elapsed_deadline_is_reported_not_scheduled_as_on_time(client, headers):
    late = task(client, headers, due_date="2026-09-27", due_time="18:00", estimated_minutes=20)
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert all(i["task_id"] != late["id"] for i in plan["items"])
    assert any(i["task_id"] == late["id"] and i["reason"] == "deadline_passed" for i in plan["unscheduled"])


def test_three_hours_balances_assignment_exam_and_poor_sleep(client, headers):
    assignment = task(client, headers, due_date="2026-09-27", due_time="20:00", estimated_minutes=55)
    java = client.post("/api/study/subjects", headers=headers, json={"name": "Java"}).json()
    dbms = client.post("/api/study/subjects", headers=headers, json={"name": "DBMS"}).json()
    client.post(
        "/api/study/exams",
        headers=headers,
        json={"subject_id": java["id"], "title": "Final", "exam_date": "2026-09-28"},
    )
    for subject in (java, dbms):
        client.post(
            "/api/study/backlog",
            headers=headers,
            json={"subject_id": subject["id"], "title": "Revision", "estimated_minutes": 90},
        )
    client.put("/api/sleep/2026-09-27", headers=headers, json={"duration_minutes": 280, "quality": 2})
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["items"][0]["task_id"] == assignment["id"]
    study = [i for i in plan["items"] if i["category"] == "study"]
    assert study and study[0]["subject_id"] == java["id"]
    from app.modules.ai.constraints import minutes

    assert all(minutes(i["end"]) - minutes(i["start"]) <= 35 for i in study)
    assert all("19:00" <= i["start"] < i["end"] <= "22:00" for i in plan["items"])
    assert all(a["end"] <= b["start"] for a, b in zip(plan["items"], plan["items"][1:], strict=False))
    assert any(i["subject_id"] == dbms["id"] for i in plan["unscheduled"])


def test_unknown_extra_fields_and_duplicate_tasks_are_rejected(app, client, headers):
    task(client, headers, estimated_minutes=30)

    class Invalid:
        name = "external"

        def generate(self, context):
            item = {"start": "19:00", "end": "19:30", "category": "task", "title": "x", "task_ref": "t1"}
            return AIPlanContent(summary="duplicate", items=[item, {**item, "start": "20:00", "end": "20:30"}])

    app.dependency_overrides[get_provider] = Invalid
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["is_fallback"]
    with pytest.raises(ValueError):
        AIPlanContent.model_validate({"summary": "x", "accepted": True})


def test_legacy_plans_remain_readable_without_claiming_new_validation(client, headers, db):
    from app.modules.ai.models import AIPlan

    client.post("/api/ai/daily-plan", headers=headers, json={})
    row = db.query(AIPlan).one()
    row.content = {k: v for k, v in row.content.items() if k in ("summary", "items", "tips", "adjustments")}
    db.commit()
    plan = client.get("/api/ai/daily-plan", headers=headers).json()
    assert plan["validation_version"] == 0
    assert plan["unscheduled"] == [] and plan["window_start"] is None


def test_after_day_end_reports_capacity_without_inventing_a_missed_deadline(client, headers, monkeypatch):
    monkeypatch.setattr("app.core.time.utcnow", lambda: datetime(2026, 9, 27, 23, tzinfo=UTC))
    task(client, headers, estimated_minutes=30)
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["items"] == []
    assert plan["window_start"] == plan["window_end"] == "22:00"
    assert plan["unscheduled"][0]["reason"] == "not_scheduled"


def test_short_task_can_use_the_last_minutes_of_the_window(client, headers, monkeypatch):
    monkeypatch.setattr("app.core.time.utcnow", lambda: datetime(2026, 9, 27, 21, 50, tzinfo=UTC))
    short = task(client, headers, estimated_minutes=5)
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["items"][0]["task_id"] == short["id"]
    assert plan["items"][0]["end"] == "21:55"
