"""Study blocks marked done become study time, once, without double counting Focus time."""

import uuid

import pytest

from app.modules.ai.models import AIPlan
from tests.conftest import TODAY, auth_headers, register

DAY = TODAY.isoformat()  # 10 March 2026; the frozen clock is 12:00 UTC


@pytest.fixture
def setup(client, db):
    """A user (UTC) with a subject and today's plan: a 09:00–10:00 study block and a task."""
    payload = register(client)
    headers = auth_headers(payload)
    subject = client.post("/api/study/subjects", json={"name": "DBMS", "color": "#3366ff"}, headers=headers).json()
    db.add(
        AIPlan(
            user_id=uuid.UUID(payload["user"]["id"]),
            plan_date=TODAY,
            revision=1,
            source="rules",
            is_fallback=False,
            content={
                "summary": "Plan",
                "items": [
                    {
                        "item_key": "study-key",
                        "start": "09:00",
                        "end": "10:00",
                        "category": "study",
                        "title": "DBMS: Revision",
                        "subject_id": subject["id"],
                    },
                    {"item_key": "task-key", "start": "10:30", "end": "11:00", "category": "task", "title": "Essay"},
                ],
                "tips": [],
                "adjustments": [],
            },
        )
    )
    db.commit()
    return headers, subject


def outcome(client, headers, key, status=None, **extra):
    url = f"/api/ai/daily-plan/{DAY}/items/{key}/outcome"
    if status is None:
        return client.delete(url, headers=headers)
    return client.put(url, headers=headers, json={"status": status, **extra})


def sessions(client, headers):
    return client.get(f"/api/study/sessions?from={DAY}&to={DAY}", headers=headers).json()


def studied(client, headers):
    return client.get("/api/dashboard", headers=headers).json()["today"]["study_minutes"]


def focus(client, headers, start, minutes):
    return client.post(
        "/api/study/sessions",
        headers=headers,
        json={"duration_minutes": minutes, "source": "focus", "started_at": f"{DAY}T{start}:00Z"},
    )


def test_done_study_block_is_logged_once_for_its_subject_date_and_length(client, setup):
    headers, subject = setup
    assert sessions(client, headers) == [] and studied(client, headers) == 0  # untouched: nothing

    response = outcome(client, headers, "study-key", "done")
    assert response.status_code == 200, response.text
    block = next(item for item in response.json()["items"] if item["item_key"] == "study-key")
    assert block["outcome"] == "done" and block["start"] == "09:00"  # schedule unchanged
    [session] = sessions(client, headers)
    assert session["source"] == "plan"
    assert session["duration_minutes"] == 60
    assert session["session_date"] == DAY
    assert session["subject"]["id"] == subject["id"]
    assert studied(client, headers) == 60

    # Repeating the same check-off never adds a second session.
    outcome(client, headers, "study-key", "done")
    assert len(sessions(client, headers)) == 1 and studied(client, headers) == 60


def test_partial_counts_only_the_minutes_given(client, setup):
    headers, _ = setup
    assert outcome(client, headers, "study-key", "partial").status_code == 200
    assert sessions(client, headers) == []  # no minutes, no credit
    outcome(client, headers, "study-key", "partial", minutes=20)
    assert [s["duration_minutes"] for s in sessions(client, headers)] == [20]
    plan = client.get("/api/ai/daily-plan", headers=headers).json()
    block = next(item for item in plan["items"] if item["item_key"] == "study-key")
    assert block["outcome"] == "partial" and block["outcome_minutes"] == 20
    # Partly done can't be the whole block, and minutes belong to partly done only.
    assert outcome(client, headers, "study-key", "partial", minutes=60).status_code == 422
    assert outcome(client, headers, "study-key", "done", minutes=30).status_code == 422
    assert [s["duration_minutes"] for s in sessions(client, headers)] == [20]


def test_skipped_cleared_and_other_blocks_are_not_study(client, setup):
    headers, _ = setup
    outcome(client, headers, "study-key", "done")
    outcome(client, headers, "study-key", "skipped")
    assert sessions(client, headers) == [] and studied(client, headers) == 0
    outcome(client, headers, "study-key", "done")
    assert outcome(client, headers, "study-key").status_code == 200  # cleared
    assert sessions(client, headers) == []
    outcome(client, headers, "task-key", "done")
    assert sessions(client, headers) == []


def test_focus_time_inside_the_block_is_not_counted_twice(client, setup):
    headers, _ = setup
    # Focus first (09:10–09:35), then the block is checked off.
    assert focus(client, headers, "09:10", 25).status_code == 201
    outcome(client, headers, "study-key", "done")
    by_source = {s["source"]: s["duration_minutes"] for s in sessions(client, headers)}
    assert by_source == {"focus": 25, "plan": 35}
    assert studied(client, headers) == 60


def test_focus_logged_after_the_check_off_reduces_the_credit_and_back(client, setup):
    headers, _ = setup
    outcome(client, headers, "study-key", "done")
    focus_session = focus(client, headers, "09:40", 25).json()  # 20 of its minutes are inside the block
    by_source = {s["source"]: s["duration_minutes"] for s in sessions(client, headers)}
    assert by_source == {"focus": 25, "plan": 40}
    assert studied(client, headers) == 65  # 60 planned + 5 Focus minutes after the block
    client.delete(f"/api/study/sessions/{focus_session['id']}", headers=headers)
    assert [s["duration_minutes"] for s in sessions(client, headers)] == [60]


def test_focus_covering_the_whole_block_leaves_nothing_to_credit(client, setup):
    headers, _ = setup
    focus(client, headers, "08:55", 70)
    outcome(client, headers, "study-key", "done")
    assert [s["source"] for s in sessions(client, headers)] == ["focus"]
    assert studied(client, headers) == 70


def test_focus_elsewhere_in_the_day_is_separate(client, setup):
    headers, _ = setup
    focus(client, headers, "11:00", 25)
    outcome(client, headers, "study-key", "done")
    assert studied(client, headers) == 85


def test_credit_is_owner_scoped_and_survives_manual_deletion(client, setup):
    headers, subject = setup
    other = auth_headers(register(client))
    assert outcome(client, other, "study-key", "done").status_code == 404
    assert sessions(client, other) == []
    outcome(client, headers, "study-key", "done")
    [session] = sessions(client, headers)
    assert client.delete(f"/api/study/sessions/{session['id']}", headers=other).status_code == 404
    # The owner may delete the credited session; the outcome stays, and checking it again re-credits.
    assert client.delete(f"/api/study/sessions/{session['id']}", headers=headers).status_code == 204
    assert sessions(client, headers) == []
    outcome(client, headers, "study-key", "done")
    assert len(sessions(client, headers)) == 1
    # A deleted subject leaves the minutes, without the subject.
    client.delete(f"/api/study/subjects/{subject['id']}", headers=headers)
    outcome(client, headers, "study-key", "done")
    [session] = sessions(client, headers)
    assert session["subject"] is None and session["duration_minutes"] == 60


def test_progress_and_insights_history_include_check_offs(client, setup):
    headers, _ = setup
    outcome(client, headers, "study-key", "done")
    history = client.get("/api/progress?days=1", headers=headers).json()["history"]
    assert history[-1]["study_minutes"] == 60
