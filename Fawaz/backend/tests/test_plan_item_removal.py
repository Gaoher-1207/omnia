"""Removing a block from a plan: persisted, owner-scoped, and nothing else changes."""

from datetime import UTC, datetime

import pytest

from tests.test_manual_plan_items import TODAY, TOMORROW, add, new_task, plan_for
from tests.test_replanning import make_proposal, setup_day


@pytest.fixture
def fixed_clock(clock):
    now = datetime(2026, 10, 4, 9, 0, tzinfo=UTC)
    clock.set(now)
    return now


def remove(client, headers, key, day=TODAY, base_revision=None):
    query = f"?base_revision={base_revision}" if base_revision is not None else ""
    return client.delete(f"/api/ai/daily-plan/{day}/items/{key}{query}", headers=headers)


def keyed(plan):
    return {item["item_key"]: item for item in plan["items"]}


def test_a_generated_block_is_removed_and_its_task_kept(client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    block = next(item for item in plan["items"] if item["task_id"])
    response = remove(client, headers, block["item_key"], base_revision=plan["revision"])
    assert response.status_code == 200, response.text
    updated = response.json()
    assert updated["revision"] == plan["revision"] + 1
    expected = keyed(plan)
    del expected[block["item_key"]]
    assert keyed(updated) == expected
    # Persisted: a reload doesn't bring it back.
    assert plan_for(client, headers).json() == updated
    task = client.get(f"/api/tasks/{block['task_id']}", headers=headers)
    assert task.status_code == 200 and task.json()["status"] == "todo"


def test_a_manual_block_is_removed(client, headers, fixed_clock):
    plan = add(client, headers, TOMORROW, category="other", title="Dentist", start="10:00", duration_minutes=60).json()
    plan = add(client, headers, TOMORROW, category="other", title="Call", start="12:00", duration_minutes=30).json()
    dentist = next(item for item in plan["items"] if item["title"] == "Dentist")
    response = remove(client, headers, dentist["item_key"], TOMORROW, plan["revision"])
    assert response.status_code == 200, response.text
    assert [item["title"] for item in plan_for(client, headers, TOMORROW).json()["items"]] == ["Call"]


def test_finished_work_stays_finished(client, headers, fixed_clock):
    subject = client.post("/api/study/subjects", headers=headers, json={"name": "DBMS"}).json()
    task = new_task(client, headers)
    add(client, headers, category="study", subject_id=subject["id"], start="10:00", duration_minutes=45)
    plan = add(client, headers, category="task", task_id=task["id"], start="11:00", duration_minutes=30).json()
    for item in plan["items"]:
        done = client.put(
            f"/api/ai/daily-plan/{TODAY}/items/{item['item_key']}/outcome", headers=headers, json={"status": "done"}
        )
        assert done.status_code == 200, done.text
    sessions = client.get("/api/study/sessions", headers=headers).json()
    assert [(s["source"], s["duration_minutes"]) for s in sessions] == [("plan", 45)]

    latest = plan_for(client, headers).json()
    for item in latest["items"]:
        assert remove(client, headers, item["item_key"]).status_code == 200
    assert plan_for(client, headers).json()["items"] == []
    assert client.get("/api/study/sessions", headers=headers).json() == sessions
    assert client.get(f"/api/tasks/{task['id']}", headers=headers).json()["status"] == "done"


def test_other_blocks_keep_their_outcomes(client, headers, fixed_clock):
    plan = add(client, headers, category="other", title="A", start="10:00", duration_minutes=30).json()
    plan = add(client, headers, category="other", title="B", start="11:00", duration_minutes=30).json()
    a, b = plan["items"]
    client.put(f"/api/ai/daily-plan/{TODAY}/items/{a['item_key']}/outcome", headers=headers, json={"status": "skipped"})
    updated = remove(client, headers, b["item_key"]).json()
    assert [(item["item_key"], item["outcome"]) for item in updated["items"]] == [(a["item_key"], "skipped")]


def test_a_stale_view_removes_nothing(client, headers, fixed_clock):
    plan = add(client, headers, category="other", title="A", start="10:00", duration_minutes=30).json()
    add(client, headers, category="other", title="B", start="11:00", duration_minutes=30)
    response = remove(client, headers, plan["items"][0]["item_key"], base_revision=plan["revision"])
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "plan_stale"
    assert [item["title"] for item in plan_for(client, headers).json()["items"]] == ["A", "B"]


def test_a_block_that_is_gone_is_never_confused_with_another(client, headers, fixed_clock):
    plan = add(client, headers, category="other", title="A", start="10:00", duration_minutes=30).json()
    key = plan["items"][0]["item_key"]
    assert remove(client, headers, key).status_code == 200
    again = remove(client, headers, key)
    assert again.status_code == 409
    assert again.json()["error"]["code"] == "plan_item_stale"


def test_fixed_commitments_are_not_plan_blocks(client, headers, fixed_clock):
    commitment = client.post(
        "/api/commitments",
        headers=headers,
        json={
            "title": "Lab",
            "category": "class",
            "kind": "one_off",
            "day": TOMORROW,
            "start_minutes": 600,
            "end_minutes": 660,
        },
    ).json()
    add(client, headers, TOMORROW, category="other", title="Call", start="12:00", duration_minutes=30)
    response = remove(client, headers, commitment["id"], TOMORROW)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "plan_item_stale"
    assert [row["id"] for row in client.get("/api/commitments", headers=headers).json()] == [commitment["id"]]


def test_only_the_owner_can_remove(client, headers, other_headers, fixed_clock):
    plan = add(client, headers, category="other", title="Mine", start="10:00", duration_minutes=30).json()
    key = plan["items"][0]["item_key"]
    assert remove(client, other_headers, key).status_code == 404
    add(client, other_headers, category="other", title="Theirs", start="10:00", duration_minutes=30)
    assert remove(client, other_headers, key).status_code == 409
    assert [item["title"] for item in plan_for(client, headers).json()["items"]] == ["Mine"]


def test_past_days_and_missing_plans(client, headers, fixed_clock):
    assert remove(client, headers, "x", "2026-10-03").status_code == 422
    assert remove(client, headers, "x", TOMORROW).status_code == 404


def test_a_replan_prepared_before_a_removal_goes_stale(client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers)
    assert proposal.status_code == 201, proposal.text
    assert remove(client, headers, plan["items"][-1]["item_key"]).status_code == 200
    applied = client.post(f"/api/ai/replan/proposals/{proposal.json()['id']}/apply", headers=headers)
    assert applied.status_code == 409
    assert applied.json()["error"]["code"] == "replan_proposal_stale"
