import json
from datetime import UTC, date, datetime, timedelta

import httpx
import pytest

from app.modules.ai.providers import AnthropicProvider, ProviderError, RulesProvider
from app.modules.ai.schemas import AIPlanContent, ContextStreak, DayStats, PlanContext
from app.modules.ai.service import get_provider

NOW = datetime(2026, 3, 10, 7, 0, tzinfo=UTC)


@pytest.fixture(autouse=True)
def frozen(monkeypatch):
    monkeypatch.setattr("app.core.time.utcnow", lambda: NOW)
    monkeypatch.setattr("app.modules.tasks.service.utcnow", lambda: NOW)


def use_provider(app, provider):
    app.dependency_overrides[get_provider] = lambda: provider


def seed(client, headers):
    subject = client.post("/api/study/subjects", json={"name": "Physics"}, headers=headers).json()
    client.post(
        "/api/study/exams",
        json={
            "subject_id": subject["id"],
            "title": "Final",
            "exam_date": (NOW.date() + timedelta(days=8)).isoformat(),
        },
        headers=headers,
    )
    client.post(
        "/api/study/backlog",
        json={
            "subject_id": subject["id"],
            "title": "Thermodynamics",
            "estimated_minutes": 120,
        },
        headers=headers,
    )
    tasks = [
        client.post("/api/tasks", json={"title": t, "priority": p}, headers=headers).json()
        for t, p in (("Email professor", "high"), ("Buy groceries", "low"), ("Lab prep", "medium"))
    ]
    return tasks


def stats(**kw):
    base = dict(study_minutes=0, tasks_completed=0, steps=0, workout_done=False)
    base.update(kw)
    return DayStats(**base)


def context(**kw):
    base = dict(
        date=date(2026, 3, 10),
        weekday="Tuesday",
        current_time="07:00",
        goals={"study_minutes": 240, "steps": 8000, "tasks": 5},
        preferred_workout_time="evening",
        today=stats(),
        yesterday=stats(workout_done=True, study_minutes=240),
        streaks={k: ContextStreak(current=0, active_today=False) for k in ("study", "tasks", "fitness", "balance")},
        exams=[],
        study_blocks=[],
        open_tasks=[],
        note=None,
    )
    base.update(kw)
    return PlanContext(**base)


# ---- rules provider (pure)


def test_rules_plan_is_valid_and_ordered():
    plan = RulesProvider().generate(context())
    assert isinstance(plan, AIPlanContent)
    starts = [i.start for i in plan.items]
    assert starts == sorted(starts)
    assert any(i.category == "fitness" and i.start == "18:00" for i in plan.items)


def test_rules_adapts_to_missed_workout_and_tiredness():
    missed = RulesProvider().generate(context(yesterday=stats(workout_done=False)))
    assert any("missed" in a for a in missed.adjustments)
    workout = next(i for i in missed.items if i.category == "fitness" and "Workout" in i.title)
    assert (int(workout.end[:2]) * 60 + int(workout.end[3:])) - (
        int(workout.start[:2]) * 60 + int(workout.start[3:])
    ) == 30

    tired = RulesProvider().generate(context(note="Slept badly, feeling tired"))
    assert any("energy" in a for a in tired.adjustments)
    assert any("Light" in i.title for i in tired.items)


def test_rules_late_evening_returns_wind_down():
    plan = RulesProvider().generate(context(current_time="21:50"))
    assert plan.items == []
    assert "nearly over" in plan.summary


# ---- endpoint


def test_daily_plan_generate_then_reuse_then_regenerate(client, headers):
    tasks = seed(client, headers)
    first = client.post("/api/ai/daily-plan", json={}, headers=headers)
    assert first.status_code == 201
    plan = first.json()
    assert plan["source"] == "rules" and plan["is_fallback"] is False
    assert plan["plan_date"] == "2026-03-10"
    assert "Physics exam" not in plan["summary"] or "8 days" in plan["summary"]
    task_ids = {i["task_id"] for i in plan["items"] if i["category"] == "task"}
    assert task_ids <= {t["id"] for t in tasks} and task_ids
    assert any(i["category"] == "study" and "Thermodynamics" in i["title"] for i in plan["items"])

    again = client.post("/api/ai/daily-plan", json={}, headers=headers)
    assert again.status_code == 200 and again.json()["id"] == plan["id"]

    fresh = client.post("/api/ai/daily-plan", json={"regenerate": True, "note": "tired"}, headers=headers)
    assert fresh.status_code == 201 and fresh.json()["id"] != plan["id"]
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == fresh.json()["id"]


def test_get_plan_404_when_none(client, headers):
    response = client.get("/api/ai/daily-plan", headers=headers)
    assert response.status_code == 404


def test_plans_are_private(client, headers, other_headers):
    client.post("/api/ai/daily-plan", json={}, headers=headers)
    assert client.get("/api/ai/daily-plan", headers=other_headers).status_code == 404


def test_note_is_limited(client, headers):
    assert client.post("/api/ai/daily-plan", json={"note": "x" * 281}, headers=headers).status_code == 422


def test_generation_is_rate_limited(client, headers, monkeypatch):
    from app.core.config import get_settings

    monkeypatch.setattr(get_settings(), "ai_rate_limit_per_hour", 2)
    codes = [
        client.post("/api/ai/daily-plan", json={"regenerate": True}, headers=headers).status_code for _ in range(3)
    ]
    assert codes == [201, 201, 429]
    assert client.post("/api/ai/daily-plan", json={}, headers=headers).status_code == 200


# ---- external provider: success, failures, and what gets sent


def _anthropic(handler):
    transport = httpx.MockTransport(handler)
    return AnthropicProvider(
        api_key="test-key",
        model="test-model",
        base_url="https://ai.invalid",
        timeout=5,
        client=httpx.Client(transport=transport),
    )


def _reply(obj):
    return httpx.Response(200, json={"content": [{"type": "text", "text": json.dumps(obj)}]})


def test_anthropic_success_maps_task_refs_and_drops_invented_ones(app, client, headers, user):
    tasks = seed(client, headers)
    sent = {}

    def handler(request):
        sent["headers"] = request.headers
        sent["body"] = json.loads(request.content)
        return _reply(
            {
                "summary": "Physics first.",
                "items": [
                    {"start": "09:00", "end": "09:50", "category": "study", "title": "Thermodynamics"},
                    {
                        "start": "10:00",
                        "end": "10:30",
                        "category": "task",
                        "title": "Email professor",
                        "task_ref": "t1",
                    },
                    {"start": "11:00", "end": "11:30", "category": "task", "title": "Made up", "task_ref": "t99"},
                ],
                "tips": ["Drink water"],
                "adjustments": [],
            }
        )

    use_provider(app, _anthropic(handler))
    response = client.post("/api/ai/daily-plan", json={"note": "busy afternoon"}, headers=headers)
    assert response.status_code == 201
    plan = response.json()
    assert plan["source"] == "anthropic" and plan["is_fallback"] is False
    assert plan["items"][1]["task_id"] == tasks[0]["id"]
    assert plan["items"][2]["task_id"] is None

    assert sent["headers"]["x-api-key"] == "test-key"
    payload = sent["body"]["messages"][0]["content"]
    assert user["user"]["email"] not in payload
    assert user["user"]["profile"]["display_name"] not in payload
    assert user["user"]["id"] not in payload
    assert tasks[0]["id"] not in payload
    assert "busy afternoon" in payload


@pytest.mark.parametrize(
    "handler, reason",
    [
        (lambda r: (_ for _ in ()).throw(httpx.ReadTimeout("slow")), "provider_timeout"),
        (lambda r: httpx.Response(503, json={}), "provider_unavailable"),
        (lambda r: httpx.Response(429, json={}), "provider_rate_limited"),
        (lambda r: httpx.Response(401, json={}), "provider_error"),
        (
            lambda r: httpx.Response(200, json={"content": [{"type": "text", "text": "Sure! Here's a plan..."}]}),
            "invalid_response",
        ),
        (
            lambda r: _reply(
                {
                    "summary": "x",
                    "items": [
                        {"start": "09:00", "end": "10:00", "category": "study", "title": "a"},
                        {"start": "09:30", "end": "10:30", "category": "study", "title": "overlap"},
                    ],
                }
            ),
            "invalid_response",
        ),
        (
            lambda r: _reply(
                {
                    "summary": "x",
                    "items": [
                        {"start": "25:00", "end": "26:00", "category": "study", "title": "bad time"},
                    ],
                }
            ),
            "invalid_response",
        ),
    ],
)
def test_anthropic_failures_fall_back_to_rules(app, client, headers, handler, reason):
    use_provider(app, _anthropic(handler))
    response = client.post("/api/ai/daily-plan", json={}, headers=headers)
    assert response.status_code == 201
    plan = response.json()
    assert plan["source"] == "rules" and plan["is_fallback"] is True
    assert "fallback_reason" not in plan


def test_provider_error_reason_is_recorded(app, client, headers, db):
    from app.modules.ai.models import AIPlan

    use_provider(app, _anthropic(lambda r: httpx.Response(503, json={})))
    client.post("/api/ai/daily-plan", json={}, headers=headers)
    stored = db.query(AIPlan).one()
    assert stored.fallback_reason == "provider_unavailable"


def test_provider_error_carries_reason():
    assert ProviderError("x").reason == "x"


def test_settings_require_key_for_anthropic(monkeypatch):
    from pydantic import ValidationError

    from app.core.config import Settings

    with pytest.raises(ValidationError):
        Settings(ai_provider="anthropic", ai_api_key="")
    with pytest.raises(ValidationError):
        Settings(app_env="production", auth_secret="short", database_url="postgresql+psycopg://x/y")
    with pytest.raises(ValidationError):
        Settings(app_env="production", auth_secret="x" * 40, database_url="sqlite:///prod.db")


def test_rules_splits_study_evenly():
    from app.modules.ai.schemas import ContextStudyBlock

    blocks = [ContextStudyBlock(subject="Maths", title="Series", minutes=60, reason="r")]
    plan = RulesProvider().generate(context(study_blocks=blocks))
    lengths = [
        int(i.end[:2]) * 60 + int(i.end[3:]) - int(i.start[:2]) * 60 - int(i.start[3:])
        for i in plan.items
        if i.category == "study"
    ]
    assert lengths == [30, 30]


def test_rules_does_not_judge_yesterday_on_signup_day():
    from app.modules.ai.schemas import ContextStudyBlock

    blocks = [ContextStudyBlock(subject="Maths", title="Series", minutes=60, reason="r")]
    fresh = RulesProvider().generate(
        context(account_age_days=0, yesterday=stats(workout_done=False, study_minutes=0), study_blocks=blocks)
    )
    assert fresh.adjustments == []


def test_study_items_link_to_their_subject(client, headers):
    seed(client, headers)
    plan = client.post("/api/ai/daily-plan", json={}, headers=headers).json()
    subject_id = client.get("/api/study/subjects", headers=headers).json()[0]["id"]
    study = [i for i in plan["items"] if i["category"] == "study"]
    assert study and all(i["subject_id"] == subject_id for i in study)
    assert all(i["subject_id"] is None for i in plan["items"] if i["category"] != "study")
