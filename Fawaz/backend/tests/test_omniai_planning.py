import json
from datetime import UTC, datetime

import httpx
import pytest

from app.core.config import get_settings
from app.modules.ai.models import AIPlan
from app.modules.ai.ollama import OllamaPlanProvider
from app.modules.ai.service import get_provider


@pytest.fixture(autouse=True)
def clock(monkeypatch):
    monkeypatch.setattr("app.core.time.utcnow", lambda: datetime(2026, 9, 28, 9, tzinfo=UTC))


def install(app, handler):
    provider = OllamaPlanProvider(
        base_url="http://local.invalid",
        model="qwen3:8b",
        timeout=1,
        context_tokens=8192,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    app.dependency_overrides[get_provider] = lambda: provider


def candidate(**changes):
    return {
        "summary": "Work first",
        "items": [
            {
                "start": "10:00",
                "end": "10:30",
                "category": "task",
                "title": "Untrusted title",
                "task_ref": "t1",
                **changes,
            }
        ],
        "tips": [],
        "adjustments": [],
    }


def seed(client, headers):
    result = client.patch(
        "/api/profile",
        headers=headers,
        json={"planning_start_minutes": 600, "planning_end_minutes": 1200, "time_format": "12h"},
    )
    assert result.status_code == 200
    return client.post(
        "/api/tasks",
        headers=headers,
        json={"title": "Real assignment", "estimated_minutes": 30, "due_date": "2026-09-28", "due_time": "11:00"},
    ).json()


def test_structured_omniai_saved_preferences_and_links(app, client, headers, other_headers, db):
    task = seed(client, headers)

    def handler(request):
        body = json.loads(request.content)
        assert body["format"]["additionalProperties"] is False
        context = json.loads(body["messages"][1]["content"])
        assert context["planning_start_minutes"] == 600 and context["planning_end_minutes"] == 1200
        return httpx.Response(200, json={"message": {"content": json.dumps(wire(candidate()))}})

    install(app, handler)
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["source"] == "ollama" and not plan["is_fallback"]
    assert plan["items"][0]["task_id"] == task["id"] and plan["items"][0]["title"] == "Real assignment"
    assert plan["window_start"] == "10:00" and plan["window_end"] == "20:00"
    explanation = plan["explanation"]
    assert explanation["headline"] != "Work first"
    assert 1 <= len(explanation["key_reasons"]) <= 3
    assert any("task" in reason.lower() for reason in explanation["key_reasons"])
    assert "Untrusted title" not in str(explanation)
    assert db.query(AIPlan).one().content["explanation"] == explanation
    assert client.get("/api/profile", headers=headers).json()["time_format"] == "12h"
    assert client.get("/api/profile", headers=other_headers).json()["planning_start_minutes"] == 480
    assert client.get("/api/ai/daily-plan", headers=other_headers).status_code == 404
    assert client.get("/api/ai/daily-plan?date=2026-09-27", headers=headers).status_code == 404
    assert db.query(AIPlan).count() == 1


@pytest.mark.parametrize(
    "kind",
    [
        "malformed",
        "reference",
        "duration",
        "overlap",
        "window",
        "deadline",
        "study",
        "capacity",
        "timeout",
        "unavailable",
    ],
)
def test_omniai_rejection_falls_back_and_only_valid_result_persists(app, client, headers, db, kind):
    seed(client, headers)

    def handler(request):
        if kind == "timeout":
            raise httpx.ReadTimeout("timeout")
        if kind == "unavailable":
            return httpx.Response(503)
        value = candidate()
        if kind == "reference":
            value = candidate(task_ref="t999")
        if kind == "duration":
            value = candidate(end="10:15")
        if kind == "window":
            value = candidate(start="09:00", end="09:30")
        if kind == "deadline":
            value = candidate(start="11:00", end="11:30")
        if kind == "capacity":
            value = candidate(end="23:00")
        if kind == "overlap":
            value["items"].append({"start": "10:15", "end": "10:40", "title": "Break", "category": "break"})
        if kind == "study":
            value = candidate(category="study", task_ref=None, study_ref="b999")
        return httpx.Response(
            200, json={"message": {"content": "not JSON" if kind == "malformed" else json.dumps(wire(value))}}
        )

    install(app, handler)
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["source"] == "rules" and plan["is_fallback"]
    assert all("10:00" <= i["start"] < i["end"] <= "20:00" for i in plan["items"])
    assert db.query(AIPlan).count() == 1
    assert db.query(AIPlan).one().source == "rules"


def test_invalid_preferences_are_atomic(client, headers):
    seed(client, headers)
    for changes in (
        {"planning_end_minutes": 599},
        {"planning_start_minutes": 1300},
        {"planning_end_minutes": None},
        {"time_format": "bad"},
    ):
        assert client.patch("/api/profile", headers=headers, json=changes).status_code == 422
    assert client.get("/api/profile", headers=headers).json()["planning_end_minutes"] == 1200


def test_shared_configuration_preserves_legacy_when_unset(monkeypatch):
    from app.modules.ai.assistant import OllamaChatProvider, get_chat_provider

    settings = get_settings()
    monkeypatch.setattr(settings, "planner_ai_provider", None)
    monkeypatch.setattr(settings, "assistant_provider", None)
    monkeypatch.setattr(settings, "omnia_ai_provider", "ollama")
    assert isinstance(get_provider(), OllamaPlanProvider)
    assert isinstance(get_chat_provider(), OllamaChatProvider)
    monkeypatch.setattr(settings, "omnia_ai_provider", None)
    monkeypatch.setattr(settings, "assistant_provider", "off")
    assert get_chat_provider() is None
    assert get_provider().name == "rules"


def test_excessive_real_study_budget_falls_back(app, client, headers, db):
    client.patch("/api/profile", headers=headers, json={"daily_study_goal_minutes": 30})
    subject = client.post("/api/study/subjects", headers=headers, json={"name": "Java"}).json()
    client.post(
        "/api/study/backlog",
        headers=headers,
        json={"subject_id": subject["id"], "title": "Revision", "estimated_minutes": 30},
    )
    value = candidate(category="study", task_ref=None, study_ref="b1", start="10:00", end="11:00")
    install(app, lambda request: httpx.Response(200, json={"message": {"content": json.dumps(wire(value))}}))
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["is_fallback"] and plan["source"] == "rules"
    assert db.query(AIPlan).count() == 1


def test_saved_narrow_window_constrains_rules_without_an_external_provider(client, headers):
    client.patch("/api/profile", headers=headers, json={"planning_start_minutes": 600, "planning_end_minutes": 620})
    client.post("/api/tasks", headers=headers, json={"title": "Too large", "estimated_minutes": 30})
    plan = client.post("/api/ai/daily-plan", headers=headers, json={}).json()
    assert plan["source"] == "rules" and not plan["is_fallback"]
    assert plan["window_start"] == "10:00" and plan["window_end"] == "10:20"
    assert plan["unscheduled"][0]["remaining_minutes"] == 30
    assert all("10:00" <= i["start"] < i["end"] <= "10:20" for i in plan["items"])


def test_older_persisted_plan_without_explanation_remains_readable(client, headers, db):
    response = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert response.status_code == 201
    row = db.query(AIPlan).one()
    row.content = {key: value for key, value in row.content.items() if key != "explanation"}
    db.commit()
    saved = client.get("/api/ai/daily-plan", headers=headers)
    assert saved.status_code == 200
    assert saved.json()["explanation"] is None


def wire(value):
    from app.modules.ai.constraints import minutes

    return {
        **value,
        "items": [
            {
                **{k: v for k, v in item.items() if k != "end"},
                "duration_minutes": minutes(item["end"]) - minutes(item["start"]),
            }
            for item in value["items"]
        ],
    }
