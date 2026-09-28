import json
from datetime import UTC, datetime

import httpx
import pytest

from app.modules.ai.constraints import hhmm, minutes
from app.modules.ai.models import AIPlan
from app.modules.ai.ollama import OllamaPlanProvider
from app.modules.ai.providers import ProviderError
from app.modules.ai.schemas import AIPlanContent
from app.modules.ai.service import get_provider
from app.modules.commitments.service import free_intervals


@pytest.fixture(autouse=True)
def clock(monkeypatch):
    monkeypatch.setattr("app.core.time.utcnow", lambda: datetime(2026, 9, 28, 8, tzinfo=UTC))


def body(title="College", **changes):
    return {
        "title": title,
        "category": "college",
        "kind": "recurring",
        "weekdays": [0, 1, 2, 3, 4],
        "start_minutes": 555,
        "end_minutes": 945,
        "enabled": True,
        **changes,
    }


def add(client, headers, data):
    response = client.post("/api/commitments", headers=headers, json=data)
    assert response.status_code == 201, response.text
    return response.json()


def test_interval_subtraction_merges_overlap_and_adjacency_and_clips():
    busy, free = free_intervals(480, 1320, [(300, 540), (540, 960), (930, 1020), (1140, 1200), (1400, 1430)])
    assert [(i.start_minutes, i.end_minutes) for i in busy] == [(480, 1020), (1140, 1200)]
    assert [(i.start_minutes, i.end_minutes) for i in free] == [(1020, 1140), (1200, 1320)]
    assert free_intervals(480, 1320, [])[1][0].end_minutes == 1320
    assert free_intervals(480, 1320, [(0, 1439)])[1] == []
    assert free_intervals(480, 1320, [(0, 400), (1350, 1400)])[1][0].start_minutes == 480


def test_recurring_and_one_off_dates_are_account_scoped(client, headers, other_headers):
    college = add(client, headers, body())
    appointment = add(
        client,
        headers,
        body(
            "Doctor appointment",
            category="appointment",
            kind="one_off",
            weekdays=[],
            day="2026-10-03",
            start_minutes=840,
            end_minutes=900,
        ),
    )
    monday = client.get("/api/commitments/availability?day=2026-09-28", headers=headers).json()
    saturday = client.get("/api/commitments/availability?day=2026-10-03", headers=headers).json()
    sunday = client.get("/api/commitments/availability?day=2026-10-04", headers=headers).json()
    assert [row["id"] for row in monday["commitments"]] == [college["id"]]
    assert [row["id"] for row in saturday["commitments"]] == [appointment["id"]]
    assert sunday["commitments"] == []
    assert client.get("/api/commitments", headers=other_headers).json() == []
    other_day = client.get("/api/commitments/availability?day=2026-09-28", headers=other_headers).json()
    assert other_day["free_intervals"] == [
        {"start_minutes": 480, "end_minutes": 1320}
    ]
    assert client.delete(f"/api/commitments/{college['id']}", headers=other_headers).status_code == 404
    assert client.put(f"/api/commitments/{college['id']}", headers=other_headers, json=body()).status_code == 404


def test_validation_and_edit_delete(client, headers):
    for invalid in (
        body(start_minutes=900, end_minutes=900),
        body(weekdays=[]),
        body(weekdays=[0, 0]),
        body(weekdays=[7]),
        body(kind="one_off", weekdays=[], day=None),
    ):
        assert client.post("/api/commitments", headers=headers, json=invalid).status_code == 422
    row = add(client, headers, body())
    changed = client.put(
        f"/api/commitments/{row['id']}",
        headers=headers,
        json=body("Work", category="work", start_minutes=600, end_minutes=720, enabled=False),
    )
    assert changed.status_code == 200
    assert changed.json()["title"] == "Work" and not changed.json()["enabled"]
    assert client.get("/api/commitments/availability?day=2026-09-28", headers=headers).json()["commitments"] == []
    assert client.delete(f"/api/commitments/{row['id']}", headers=headers).status_code == 204
    assert client.get("/api/commitments", headers=headers).json() == []


def test_rules_and_context_respect_commitments_and_saved_hours(client, headers, db):
    client.patch("/api/profile", headers=headers, json={"planning_start_minutes": 600, "planning_end_minutes": 1200})
    add(client, headers, body(start_minutes=555, end_minutes=945))
    add(client, headers, body("Commute", category="commute", start_minutes=945, end_minutes=990))
    client.post("/api/tasks", headers=headers, json={"title": "Assignment", "estimated_minutes": 30})
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["source"] == "rules"
    assert all(int(item["start"][:2]) * 60 + int(item["start"][3:]) >= 990 for item in plan["items"])
    assert plan["explanation"]["headline"] == "Fixed commitments shape the available time today."
    assert any("College" in line for line in plan["explanation"]["key_reasons"])
    assert db.query(AIPlan).count() == 1


class Candidate:
    name = "ollama"

    def __init__(self, start):
        self.start = start
        self.context = None

    def generate(self, context):
        self.context = context
        end = hhmm(minutes(self.start) + 30)
        return AIPlanContent.model_validate(
            {
                "summary": "Assignment first",
                "items": [
                    {
                        "start": self.start,
                        "end": end,
                        "category": "task",
                        "title": "Invented title",
                        "task_ref": "t1",
                    }
                ],
            }
        )


@pytest.mark.parametrize("start,source", [("09:30", "rules"), ("16:30", "ollama")])
def test_model_cannot_schedule_busy_time_and_valid_free_proposal_persists(
    app, client, headers, db, start, source
):
    add(client, headers, body())
    add(client, headers, body("Commute", category="commute", start_minutes=945, end_minutes=990))
    client.post("/api/tasks", headers=headers, json={"title": "Real task", "estimated_minutes": 30})
    provider = Candidate(start)
    app.dependency_overrides[get_provider] = lambda: provider
    result = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert result.status_code == 201, result.text
    plan = result.json()
    assert plan["source"] == source
    assert plan["is_fallback"] == (source == "rules")
    assert provider.context.commitments[0].title == "College"
    assert [(i.start_minutes, i.end_minutes) for i in provider.context.free_intervals] == [
        (480, 555),
        (990, 1320),
    ]
    assert all(not ("09:15" <= item["start"] < "16:30") for item in plan["items"])
    assert db.query(AIPlan).count() == 1
    if source == "ollama":
        assert plan["items"][0]["title"] == "Real task"
    else:
        assert all(item["title"] != "Invented title" for item in plan["items"])


def test_commitment_change_does_not_rewrite_persisted_plan(client, headers):
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    add(client, headers, body(start_minutes=480, end_minutes=1320))
    saved = client.get("/api/ai/daily-plan", headers=headers).json()
    assert saved["id"] == plan["id"] and saved["items"] == plan["items"]
    newer = client.post("/api/ai/daily-plan", headers=headers, json={"regenerate": True}).json()
    assert newer["id"] != plan["id"] and newer["items"] == []
    assert newer["source"] == "rules"


def test_ollama_receives_trusted_free_intervals_and_feasible_rules_draft(app, client, headers):
    add(client, headers, body())
    add(client, headers, body("Commute", category="commute", start_minutes=945, end_minutes=990))
    client.post("/api/tasks", headers=headers, json={"title": "Assignment", "estimated_minutes": 30})

    def handler(request):
        facts = json.loads(json.loads(request.content)["messages"][1]["content"])
        assert facts["hard_constraints"]["free_intervals"] == [
            {"start": "08:00", "end": "09:15"},
            {"start": "16:30", "end": "22:00"},
        ]
        assert all(
            item["start"] < "09:15" or item["start"] >= "16:30"
            for item in facts["rules_draft"]["items"]
        )
        return httpx.Response(
            200,
            json={"message": {"content": json.dumps({
                "summary": "Assignment around college",
                "items": [{
                    "start": "16:30",
                    "duration_minutes": 30,
                    "category": "task",
                    "title": "Untrusted title",
                    "task_ref": "t1",
                }],
                "tips": [],
                "adjustments": [],
            })}},
        )

    provider = OllamaPlanProvider(
        base_url="http://local.invalid",
        model="qwen3:8b",
        timeout=1,
        context_tokens=8192,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    app.dependency_overrides[get_provider] = lambda: provider
    result = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert result.status_code == 201
    assert result.json()["source"] == "ollama"
    assert result.json()["items"][0]["title"] == "Assignment"


def test_unavailable_provider_falls_back_inside_free_intervals(app, client, headers):
    add(client, headers, body(start_minutes=480, end_minutes=990))
    client.post("/api/tasks", headers=headers, json={"title": "Assignment", "estimated_minutes": 30})

    class Offline:
        name = "ollama"

        def generate(self, context):
            raise ProviderError("provider_timeout")

    app.dependency_overrides[get_provider] = Offline
    result = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert result.status_code == 201
    assert result.json()["source"] == "rules" and result.json()["is_fallback"]
    assert all(item["start"] >= "16:30" for item in result.json()["items"])
