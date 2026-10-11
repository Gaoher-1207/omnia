"""Adaptive planning stays fast, bounded and safe whatever the model sends back."""

import json
import logging
from datetime import UTC, datetime

import httpx
import pytest

from app.modules.ai import replan_protocol as protocol
from app.modules.ai import service
from app.modules.ai.ollama import OllamaPlanProvider
from app.modules.ai.providers import ProviderError, RulesProvider
from tests.test_replanning import configure, make_proposal, setup_day


@pytest.fixture
def fixed_clock(clock):
    now = datetime(2026, 10, 4, 9, 0, tzinfo=UTC)
    clock.set(now)
    return now


# ---- parsing: tolerant of wrapping, strict about content


@pytest.mark.parametrize(
    "text",
    [
        '{"summary": "ok", "changes": []}',
        '```json\n{"summary": "ok", "changes": []}\n```',
        'Sure! Here is the plan:\n{"summary": "ok", "changes": []}\nLet me know.',
        '{"summary": "ok {not a brace}", "changes": []} trailing } text',
    ],
)
def test_json_is_found_inside_fences_and_prose(text):
    assert protocol.parse_json_object(text)["changes"] == []


@pytest.mark.parametrize(
    ("text", "code"),
    [
        ("no json here", "no_json_object"),
        ('{"summary": "cut off", "changes": [', "truncated_json"),
        ('{"summary": "bad", "changes": [,]}', "malformed_json"),
    ],
)
def test_broken_json_is_an_error_never_patched(text, code):
    with pytest.raises(protocol.EditProtocolError, match=code):
        protocol.parse_json_object(text)


def _payload(now="09:00"):
    return {
        "request": "x",
        "current_schedule": [
            {
                "item_key": "a",
                "start": "08:00",
                "end": "08:30",
                "category": "other",
                "title": "Past",
                "detail": None,
                "task_ref": None,
                "study_ref": None,
            },
            {
                "item_key": "b",
                "start": "10:00",
                "end": "10:30",
                "category": "task",
                "title": "Essay",
                "detail": "High priority",
                "task_ref": "t1",
                "study_ref": None,
            },
            {
                "item_key": "c",
                "start": "11:00",
                "end": "12:00",
                "category": "fitness",
                "title": "Gym",
                "detail": None,
                "task_ref": None,
                "study_ref": None,
            },
        ],
        "context": {"open_tasks": [{"ref": "t1", "title": "Essay", "estimated_minutes": 30}], "study_blocks": []},
        "hard_constraints": {"earliest_start": now, "latest_end": "22:00", "free_intervals": []},
    }


def _edits(*changes, summary="Adjusted"):
    return json.dumps({"summary": summary, "explanation": "Why.", "changes": list(changes)})


def test_edits_rebuild_the_schedule_and_copy_untouched_blocks_exactly():
    draft = protocol.to_draft(
        _edits(
            {"action": "move", "key": "i2", "start": "15:00"},
            {"action": "remove", "key": "i3"},
            {"action": "add", "start": "18:00", "end": "18:45", "category": "break", "title": "Walk"},
        ),
        _payload(),
    )
    items = {item.title: item for item in draft.items}
    assert (items["Essay"].start, items["Essay"].end) == ("15:00", "15:30")  # length kept
    assert items["Essay"].task_ref == "t1" and items["Essay"].detail == "High priority"
    assert "Gym" not in items and "Past" not in items
    assert (items["Walk"].start, items["Walk"].end) == ("18:00", "18:45")


def test_no_changes_keeps_today_as_is():
    draft = protocol.to_draft(_edits(), _payload())
    assert [item.title for item in draft.items] == ["Essay", "Gym"]


@pytest.mark.parametrize(
    ("change", "code"),
    [
        ({"action": "move", "key": "i9", "start": "15:00"}, "unknown_key"),
        ({"action": "move", "key": "i1", "start": "15:00"}, "past_block_edited"),
        ({"action": "move", "key": "i2"}, "incomplete_move"),
        ({"action": "add", "start": "18:00", "category": "break", "title": "Walk"}, "incomplete_add"),
        ({"action": "explode", "key": "i2"}, "schema_mismatch"),
        ({"action": "move", "key": "i2", "start": "25:00"}, "schema_mismatch"),
        ({"action": "resize", "key": "i2", "start": "15:00", "end": "14:00"}, "invalid_block"),
    ],
)
def test_ambiguous_or_unsafe_edits_are_rejected(change, code):
    with pytest.raises(protocol.EditProtocolError, match=code):
        protocol.to_draft(_edits(change), _payload())


def test_one_block_edited_twice_is_a_conflict():
    with pytest.raises(protocol.EditProtocolError, match="conflicting_changes"):
        protocol.to_draft(
            _edits({"action": "move", "key": "i2", "start": "15:00"}, {"action": "remove", "key": "i2"}),
            _payload(),
        )


def test_the_prompt_holds_no_ids_or_identity():
    message = protocol.user_message(_payload())
    assert '"key":"i2"' in message
    assert "item_key" not in message and '"b"' not in message
    assert len(message) < 2000


# ---- the service: bounded, retried only when useful, never accepting bad answers


class ScriptedProvider:
    """Answers each call from a script; records what each call was given."""

    name = "scripted"

    def __init__(self, *answers):
        self.answers = list(answers)
        self.calls = []

    def generate(self, context):
        return RulesProvider().generate(context)

    def generate_replan(self, payload):
        self.calls.append({"timeout": payload.get("_timeout_seconds"), "feedback": payload.get("_feedback")})
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        try:  # wrapped the way the real providers wrap it
            return protocol.to_draft(answer(payload) if callable(answer) else answer, payload)
        except protocol.EditProtocolError as exc:
            raise ProviderError(f"invalid_response:{exc.code}") from None


def _task_key(payload):
    return next(key for key, item in protocol.keyed_schedule(payload) if item["category"] == "task")


def _move_task(start):
    return lambda payload: _edits({"action": "move", "key": _task_key(payload), "start": start})


def test_a_good_answer_is_used_in_one_call(app, client, headers, fixed_clock):
    provider = ScriptedProvider(_move_task("15:00"))
    configure(app, provider)
    setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers, "Move Finish assignment to 15:00")
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["validation"]["fallback_used"] is False and body["validation"]["attempts"] == 1
    assert next(i for i in body["schedule"] if i["category"] == "task")["start"] == "15:00"
    assert 0 < provider.calls[0]["timeout"] <= 45


def test_a_partial_answer_is_retried_once_with_the_reason(app, client, headers, fixed_clock):
    provider = ScriptedProvider('{"summary": "cut', _move_task("15:00"))
    configure(app, provider)
    setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers, "Move Finish assignment to 15:00")
    assert response.status_code == 201, response.text
    assert [call["feedback"] for call in provider.calls] == [None, "truncated_json"]
    assert response.json()["validation"]["attempts"] == 2
    assert response.json()["validation"]["fallback_used"] is False


def test_an_overlapping_answer_is_retried_then_replaced(app, client, headers, fixed_clock):
    def overlap(payload):
        task = _task_key(payload)
        other = next(key for key, item in protocol.keyed_schedule(payload) if key != task)
        start = dict(protocol.keyed_schedule(payload))[other]["start"]
        return _edits({"action": "move", "key": task, "start": start})

    provider = ScriptedProvider(overlap, overlap)
    configure(app, provider)
    plan = setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers)
    assert response.status_code == 201, response.text
    body = response.json()
    assert len(provider.calls) == 2
    assert body["validation"]["fallback_used"] is True
    assert body["validation"]["ai_failure"].startswith("validation:")
    assert client.get("/api/ai/daily-plan", headers=headers).json()["id"] == plan["id"]


def test_an_invented_reference_is_never_accepted(app, client, headers, fixed_clock):
    fake = _edits(
        {"action": "add", "start": "16:00", "end": "16:30", "category": "task", "title": "x", "task_ref": "t999"}
    )
    provider = ScriptedProvider(fake, fake)
    configure(app, provider)
    setup_day(client, headers, fixed_clock)
    body = make_proposal(client, headers).json()
    assert body["validation"]["fallback_used"] is True
    assert all(item.get("title") != "x" for item in body["schedule"])


def test_a_timeout_is_not_retried_and_says_so(app, client, headers, fixed_clock):
    provider = ScriptedProvider(ProviderError("provider_timeout"))
    configure(app, provider)
    setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers)
    assert response.status_code == 201, response.text
    assert len(provider.calls) == 1
    assert any("took too long" in warning for warning in response.json()["warnings"])


def test_a_timeout_on_a_request_rules_cannot_do_is_a_clear_504(app, client, headers, fixed_clock):
    configure(app, ScriptedProvider(ProviderError("provider_timeout")))
    setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers, "Move Finish assignment to 16:00")
    assert response.status_code == 504
    assert response.json()["error"]["code"] == "replan_provider_timeout"
    assert "45 seconds" in response.json()["error"]["message"]
    assert client.get("/api/ai/daily-plan", headers=headers).json()["revision"] == 1


def test_an_offline_provider_is_a_clear_503(app, client, headers, fixed_clock):
    configure(app, ScriptedProvider(ProviderError("provider_unreachable")))
    setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers, "Move Finish assignment to 16:00")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "replan_provider_unavailable"


def test_no_retry_when_the_budget_is_nearly_spent(app, client, headers, fixed_clock, monkeypatch):
    clock = {"now": 1000.0}
    monkeypatch.setattr(service.time, "monotonic", lambda: clock["now"])

    def slow_and_broken(payload):
        clock["now"] += 40  # most of the 45 s budget
        return '{"summary": "cut'

    provider = ScriptedProvider(slow_and_broken, _move_task("15:00"))
    configure(app, provider)
    setup_day(client, headers, fixed_clock)
    response = make_proposal(client, headers)
    assert response.status_code == 201
    assert len(provider.calls) == 1, "a second call wouldn't fit the budget"
    assert response.json()["validation"]["fallback_used"] is True


def test_logs_time_each_attempt_without_private_content(app, client, headers, fixed_clock, caplog):
    configure(app, ScriptedProvider('{"summary": "cut', _move_task("15:00")))
    setup_day(client, headers, fixed_clock)
    with caplog.at_level(logging.INFO):
        make_proposal(client, headers, "Move Finish assignment to 15:00 SECRET-NOTE")
    lines = [record.getMessage() for record in caplog.records if "Replan attempt" in record.getMessage()]
    assert lines[0].startswith("Replan attempt provider=scripted attempt=1 outcome=invalid_response")
    assert "latency_ms=" in lines[0]
    assert not any("SECRET-NOTE" in record.getMessage() for record in caplog.records)
    assert not any("Finish assignment" in record.getMessage() for record in caplog.records)


# ---- the local Ollama provider end to end (mocked HTTP), then apply


def _ollama(reply):
    def handler(request):
        facts = json.loads(json.loads(request.content)["messages"][1]["content"].split("\n")[0])
        return httpx.Response(200, json={"message": {"content": reply(facts)}})

    return OllamaPlanProvider(
        base_url="http://ollama.invalid",
        model="qwen3:8b",
        timeout=60,
        context_tokens=8192,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )


def test_fenced_ollama_answer_becomes_a_proposal_that_applies(app, client, headers, fixed_clock):
    def reply(facts):
        task = next(item["key"] for item in facts["schedule"] if item["category"] == "task")
        edits = {
            "summary": "Moved",
            "explanation": "Later.",
            "changes": [{"action": "move", "key": task, "start": "15:00", "reason": "free then"}],
        }
        return f"Here you go:\n```json\n{json.dumps(edits)}\n```"

    configure(app, RulesProvider())
    first = setup_day(client, headers, fixed_clock)
    configure(app, _ollama(reply))
    proposal = make_proposal(client, headers, "Move Finish assignment to 15:00")
    assert proposal.status_code == 201, proposal.text
    assert proposal.json()["validation"]["fallback_used"] is False
    assert client.get("/api/ai/daily-plan", headers=headers).json()["revision"] == first["revision"]
    applied = client.post(f"/api/ai/replan/proposals/{proposal.json()['id']}/apply", headers=headers)
    assert applied.status_code == 200, applied.text
    assert applied.json()["revision"] == first["revision"] + 1
    assert next(i for i in applied.json()["items"] if i["category"] == "task")["start"] == "15:00"


def test_ollama_timeout_maps_to_provider_timeout():
    def handler(_request):
        raise httpx.ReadTimeout("slow")

    provider = OllamaPlanProvider(
        base_url="http://ollama.invalid",
        model="m",
        timeout=60,
        context_tokens=2048,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    with pytest.raises(ProviderError, match="provider_timeout"):
        provider.generate_replan({**_payload(), "_timeout_seconds": 5})
