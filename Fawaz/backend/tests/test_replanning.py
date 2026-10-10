import json
import uuid
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import event
from sqlalchemy.orm import Session

from app.modules.ai import service
from app.modules.ai.providers import ProviderError, RulesProvider
from app.modules.ai.schemas import ReplanDraft
from app.modules.ai.service import get_provider


class ReplanningProvider:
    name = "test"

    def __init__(self, transform=None, failure=False):
        self.transform = transform
        self.failure = failure

    def generate(self, context):
        return RulesProvider().generate(context)

    def generate_replan(self, payload):
        if self.failure:
            from app.modules.ai.providers import ProviderError

            raise ProviderError(self.failure if isinstance(self.failure, str) else "provider_unavailable")
        items = [
            {key: item.get(key) for key in ("start", "end", "category", "title", "detail", "task_ref", "study_ref")}
            for item in payload["current_schedule"]
        ]
        if self.transform:
            items = self.transform(items)
        return ReplanDraft(
            summary="Adjusted plan",
            explanation="The requested change fits today's constraints.",
            items=items,
        )


@pytest.fixture
def fixed_clock(monkeypatch):
    now = datetime(2026, 10, 4, 9, 0, tzinfo=UTC)
    monkeypatch.setattr(service, "local_now", lambda _tz: now)
    monkeypatch.setattr(service, "utcnow", lambda: now)
    monkeypatch.setattr("app.core.time.utcnow", lambda: now)
    return now


def configure(app, provider):
    app.dependency_overrides[get_provider] = lambda: provider


def setup_day(client, headers, fixed_clock):
    client.patch(
        "/api/profile",
        headers=headers,
        json={"planning_start_minutes": 480, "planning_end_minutes": 1320},
    )
    client.post(
        "/api/tasks",
        headers=headers,
        json={
            "title": "Finish assignment",
            "estimated_minutes": 30,
            "due_date": fixed_clock.date().isoformat(),
            "due_time": "18:00",
        },
    )
    response = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert response.status_code == 201, response.text
    return response.json()


def make_proposal(client, headers, request="Keep today's plan, but make it fit the current circumstances."):
    return client.post(
        "/api/ai/replan/proposals",
        headers=headers,
        json={"request": request},
    )


def test_proposal_is_persisted_without_changing_plan(app, client, headers, fixed_clock):
    provider = ReplanningProvider()
    configure(app, provider)
    plan = setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers)
    assert proposal.status_code == 201, proposal.text
    body = proposal.json()
    assert body["status"] == "pending"
    assert body["base_plan_id"] == plan["id"]
    assert body["base_revision"] == 1
    assert "schedule" in body and "operations" in body and "validation" in body
    current = client.get("/api/ai/daily-plan", headers=headers).json()
    assert current["id"] == plan["id"]
    assert current["revision"] == 1


def test_regeneration_increments_revision(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    first = setup_day(client, headers, fixed_clock)
    second = client.post("/api/ai/daily-plan", headers=headers, json={"regenerate": True})
    assert second.status_code == 201
    assert second.json()["revision"] == first["revision"] + 1


def test_apply_creates_next_revision_and_cannot_apply_twice(app, client, headers, fixed_clock):
    def move_task(items):
        return [{**item, "start": "15:00", "end": "15:30"} if item["category"] == "task" else item for item in items]

    configure(app, ReplanningProvider(transform=move_task))
    first = setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers, "Move Finish assignment to 15:00").json()
    move = next(operation for operation in proposal["operations"] if operation["kind"] == "MOVE")
    assert move["after"]["start"] == "15:00"
    applied = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert applied.status_code == 200, applied.text
    assert applied.json()["revision"] == first["revision"] + 1
    assert applied.json()["id"] != first["id"]
    task_block = next(item for item in applied.json()["items"] if item["category"] == "task")
    assert task_block["start"] == "15:00"
    assert client.get(f"/api/ai/replan/proposals/{proposal['id']}", headers=headers).json()["status"] == "applied"
    again = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert again.status_code == 409


def test_proposal_is_private_and_dismissed_proposal_cannot_apply(app, client, headers, other_headers, fixed_clock):
    configure(app, ReplanningProvider())
    setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers).json()
    assert client.get(f"/api/ai/replan/proposals/{proposal['id']}", headers=other_headers).status_code == 404
    assert client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=other_headers).status_code == 404
    dismissed = client.post(f"/api/ai/replan/proposals/{proposal['id']}/dismiss", headers=headers)
    assert dismissed.status_code == 200 and dismissed.json()["status"] == "dismissed"
    assert client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers).status_code == 409
    assert client.post(f"/api/ai/replan/proposals/{proposal['id']}/dismiss", headers=headers).status_code == 409


def test_changed_context_marks_proposal_stale(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers).json()
    task = client.get("/api/tasks", headers=headers).json()["items"][0]
    client.patch(f"/api/tasks/{task['id']}", headers=headers, json={"title": "Changed after proposal"})
    applied = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert applied.status_code == 409
    assert applied.json()["error"]["code"] == "replan_proposal_stale"
    assert client.get(f"/api/ai/replan/proposals/{proposal['id']}", headers=headers).json()["status"] == "stale"
    assert client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers).status_code == 409


def test_time_passing_past_proposed_blocks_marks_proposal_stale(app, client, headers, fixed_clock, monkeypatch):
    configure(app, ReplanningProvider())
    setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers).json()
    first_start = min(item["start"] for item in proposal["schedule"])
    hour, minute = (int(part) for part in first_start.split(":"))
    later = datetime(2026, 10, 4, hour, minute, tzinfo=UTC) + timedelta(minutes=1)
    monkeypatch.setattr(service, "local_now", lambda _tz: later)
    monkeypatch.setattr(service, "utcnow", lambda: later)
    monkeypatch.setattr("app.core.time.utcnow", lambda: later)
    response = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "replan_proposal_stale"


def test_context_change_during_model_call_prevents_proposal_persistence(app, client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    task = client.get("/api/tasks", headers=headers).json()["items"][0]

    def change_state(items):
        updated = client.patch(f"/api/tasks/{task['id']}", headers=headers, json={"title": "Changed during model call"})
        assert updated.status_code == 200
        return items

    configure(app, ReplanningProvider(transform=change_state))
    response = make_proposal(client, headers)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "replan_proposal_stale"
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


@pytest.mark.parametrize("invalid_kind", ["overlap", "unknown_ref", "commitment"])
def test_invalid_schedule_is_rejected(app, client, headers, fixed_clock, invalid_kind):
    def transform(items):
        task = next((item for item in items if item["category"] == "task"), None)
        if invalid_kind == "unknown_ref":
            return [{"start": "09:00", "end": "09:30", "category": "task", "title": "fake", "task_ref": "t999"}]
        if invalid_kind == "commitment":
            return [{"start": "10:15", "end": "10:45", "category": "task", "title": "task", "task_ref": "t1"}]
        if task:
            return items + [{**task, "start": task["start"], "end": task["end"]}]
        return [
            {"start": "10:00", "end": "11:00", "category": "break", "title": "Break"},
            {"start": "10:30", "end": "11:30", "category": "other", "title": "Overlap"},
        ]

    provider = ReplanningProvider(transform=transform)
    configure(app, provider)
    if invalid_kind == "commitment":
        client.post(
            "/api/commitments",
            headers=headers,
            json={
                "title": "Fixed meeting",
                "category": "other",
                "kind": "one_off",
                "day": "2026-10-04",
                "start_minutes": 600,
                "end_minutes": 660,
                "enabled": True,
            },
        )
    setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers)
    assert response.status_code == 422
    assert client.get("/api/ai/daily-plan", headers=headers).status_code == 200


def test_explicit_request_intent_is_checked(app, client, headers, fixed_clock):
    def move_task(items):
        return [{**item, "start": "15:00", "end": "15:30"} if item["category"] == "task" else item for item in items]

    configure(app, ReplanningProvider(transform=move_task))
    setup_day(client, headers, fixed_clock)
    accepted = make_proposal(client, headers, "Move Finish assignment to 15:00")
    assert accepted.status_code == 201, accepted.text
    assert accepted.json()["validation"]["semantic"]["checks"] == [
        {"kind": "explicit_start_time", "result": "satisfied"}
    ]

    rejected = make_proposal(client, headers, "Move Finish assignment to 16:00")
    assert rejected.status_code == 422
    assert client.get("/api/ai/daily-plan", headers=headers).json()["revision"] == 1


def test_study_work_in_current_plan_cannot_be_removed(app, client, headers, fixed_clock):
    client.patch("/api/profile", headers=headers, json={"daily_study_goal_minutes": 120})
    subject = client.post("/api/study/subjects", headers=headers, json={"name": "Physics"}).json()
    client.post(
        "/api/study/backlog",
        headers=headers,
        json={"subject_id": subject["id"], "title": "Thermodynamics", "estimated_minutes": 90},
    )

    def remove_study(items):
        return [item for item in items if item["category"] != "study"]

    configure(app, ReplanningProvider(transform=remove_study))
    plan = setup_day(client, headers, fixed_clock)
    assert any(item["category"] == "study" for item in plan["items"])
    response = make_proposal(client, headers)
    assert response.status_code == 422
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


def test_generated_operations_are_independently_checked_on_apply(app, client, headers, db, fixed_clock):
    def move_task(items):
        return [{**item, "start": "15:00", "end": "15:30"} if item["category"] == "task" else item for item in items]

    configure(app, ReplanningProvider(transform=move_task))
    plan = setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers).json()
    from app.modules.ai.models import ReplanProposal

    row = db.query(ReplanProposal).filter_by(id=uuid.UUID(proposal["id"])).one()
    forged_operations = json.loads(json.dumps(row.operations))
    next(operation for operation in forged_operations if operation["kind"] == "MOVE")["after"]["start"] = "16:00"
    row.operations = forged_operations
    db.commit()

    response = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert response.status_code == 422
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]
    assert client.get(f"/api/ai/replan/proposals/{proposal['id']}", headers=headers).json()["status"] == "invalid"
    assert client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers).status_code == 409


def test_provider_failure_uses_deterministic_fallback_without_mutating_plan(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    configure(app, ReplanningProvider(failure=True))
    response = make_proposal(client, headers)
    assert response.status_code == 201, response.text
    assert response.json()["validation"]["fallback_used"] is True
    assert "deterministic rules planner" in " ".join(response.json()["warnings"])
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


def test_malformed_ai_output_uses_safe_rules_fallback(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    configure(app, ReplanningProvider(failure="invalid_response"))
    response = make_proposal(client, headers)
    assert response.status_code == 201, response.text
    assert response.json()["status"] == "pending"
    assert response.json()["validation"]["fallback_used"] is True
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


def test_rules_fallback_fails_closed_when_it_cannot_satisfy_explicit_request(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    configure(app, ReplanningProvider(failure=True))
    response = make_proposal(client, headers, "Move Finish assignment to 14:00")
    assert response.status_code == 503
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


def test_cross_user_entity_id_is_rejected_and_fallback_contains_only_owned_ids(
    app, client, headers, other_headers, fixed_clock
):
    foreign_task = client.post("/api/tasks", headers=other_headers, json={"title": "Private task"}).json()
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)

    class ForgedEntityProvider:
        name = "test"

        def generate(self, context):
            return RulesProvider().generate(context)

        def generate_replan(self, payload):
            from app.modules.ai.providers import ProviderError

            task = next(item for item in payload["current_schedule"] if item["category"] == "task")
            forged = {key: task.get(key) for key in ("start", "end", "category", "title", "detail", "task_ref")}
            forged["task_id"] = foreign_task["id"]
            try:
                return ReplanDraft(summary="Forged", explanation="Attempt another owner's ID.", items=[forged])
            except ValidationError:
                raise ProviderError("invalid_response") from None

    configure(app, ForgedEntityProvider())
    response = make_proposal(client, headers)
    assert response.status_code == 201, response.text
    assert response.json()["validation"]["fallback_used"] is True
    assert all(item.get("task_id") != foreign_task["id"] for item in response.json()["schedule"])
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


def test_apply_rolls_back_plan_and_lifecycle_together(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers).json()

    def fail_apply_commit(session):
        if any(getattr(row, "revision", None) == plan["revision"] + 1 for row in session.new):
            raise RuntimeError("injected commit failure")

    event.listen(Session, "before_commit", fail_apply_commit)
    try:
        with TestClient(app, raise_server_exceptions=False) as failing_client:
            response = failing_client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    finally:
        event.remove(Session, "before_commit", fail_apply_commit)
    assert response.status_code == 500
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]
    assert client.get(f"/api/ai/replan/proposals/{proposal['id']}", headers=headers).json()["status"] == "pending"


def test_expired_proposal_cannot_apply(app, client, headers, db, fixed_clock):
    configure(app, ReplanningProvider())
    setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers).json()
    from app.modules.ai.models import ReplanProposal

    row = db.query(ReplanProposal).filter_by(id=uuid.UUID(proposal["id"])).one()
    row.expires_at = datetime(2026, 10, 4, 8, 0, tzinfo=UTC)
    db.commit()
    response = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "replan_proposal_expired"


def test_chat_remains_read_only(app, client, headers, fixed_clock):
    from app.modules.ai import assistant

    class ReadOnlyChat:
        name = "test"

        def reply(self, system, messages):
            return "I can suggest a change, but I have not applied one."

    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    app.dependency_overrides[assistant.get_chat_provider] = lambda: ReadOnlyChat()
    response = client.post("/api/ai/chat", headers=headers, json={"message": "Change my plan"})
    assert response.status_code == 200
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


def test_ollama_replan_uses_structured_schema():
    from app.modules.ai.ollama import OllamaPlanProvider

    expected = {
        "summary": "Keep the plan",
        "explanation": "No changes are needed.",
        "items": [],
    }

    def handler(request):
        body = json.loads(request.content)
        assert body["format"]["additionalProperties"] is False
        return httpx.Response(200, json={"message": {"content": json.dumps(expected)}})

    provider = OllamaPlanProvider(
        base_url="http://ollama.invalid",
        model="configured",
        timeout=1,
        context_tokens=2048,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    assert provider.generate_replan({"request": "Keep the plan"}).summary == expected["summary"]


def test_openrouter_replan_uses_configured_model_and_json_schema():
    from app.modules.ai.openrouter import OpenRouterPlanProvider

    expected = {"summary": "Keep the plan", "explanation": "No changes are needed.", "items": []}

    def handler(request):
        body = json.loads(request.content)
        assert body["model"] == "configured/model"
        assert body["response_format"]["type"] == "json_schema"
        return httpx.Response(
            200,
            json={"model": "configured/model", "choices": [{"message": {"content": json.dumps(expected)}}]},
        )

    provider = OpenRouterPlanProvider(
        api_key="test",
        primary_model="configured/model",
        fallback_model="configured/fallback",
        timeout=1,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    assert provider.generate_replan({"request": "Keep the plan"}).summary == expected["summary"]


def test_openrouter_replan_rejects_malformed_ai_output():
    from app.modules.ai.openrouter import OpenRouterPlanProvider

    def handler(_request):
        return httpx.Response(
            200,
            json={"model": "configured/model", "choices": [{"message": {"content": '{"summary": ""}'}}]},
        )

    provider = OpenRouterPlanProvider(
        api_key="test",
        primary_model="configured/model",
        fallback_model="configured/fallback",
        timeout=1,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    with pytest.raises(ProviderError, match="invalid_response"):
        provider.generate_replan({"request": "Keep the plan"})
