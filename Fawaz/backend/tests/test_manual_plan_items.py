"""Adding blocks to a plan by hand: persisted, owner-scoped, never moving anything."""

from datetime import UTC, datetime

import pytest

from tests.test_replanning import make_proposal, setup_day

TODAY = "2026-10-04"
TOMORROW = "2026-10-05"


@pytest.fixture
def fixed_clock(clock):
    now = datetime(2026, 10, 4, 9, 0, tzinfo=UTC)
    clock.set(now)
    return now


def add(client, headers, day=TODAY, **body):
    return client.post(f"/api/ai/daily-plan/{day}/items", headers=headers, json=body)


def new_task(client, headers, title="Call the bank", minutes=30):
    response = client.post("/api/tasks", headers=headers, json={"title": title, "estimated_minutes": minutes})
    assert response.status_code == 201, response.text
    return response.json()


def plan_for(client, headers, day=TODAY):
    return client.get(f"/api/ai/daily-plan?date={day}", headers=headers)


def keyed(plan):
    return {item["item_key"]: (item["start"], item["end"], item["title"]) for item in plan["items"]}


def test_a_task_from_tasks_joins_todays_plan_without_moving_anything(client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    task = new_task(client, headers)
    response = add(
        client,
        headers,
        category="task",
        task_id=task["id"],
        start="22:30",
        duration_minutes=45,
        base_revision=plan["revision"],
    )
    assert response.status_code == 200, response.text
    updated = response.json()
    assert updated["revision"] == plan["revision"] + 1
    added = next(item for item in updated["items"] if item["manual"])
    assert added == {
        **added,
        "start": "22:30",
        "end": "23:15",
        "category": "task",
        "title": "Call the bank",
        "task_id": task["id"],
    }
    # Everything that was there is untouched, and the order is by time.
    assert {key: value for key, value in keyed(updated).items() if key != added["item_key"]} == keyed(plan)
    assert [item["start"] for item in updated["items"]] == sorted(item["start"] for item in updated["items"])
    # It survives a reload.
    assert plan_for(client, headers).json() == updated


def test_a_new_day_gets_a_plan_of_its_own(client, headers, fixed_clock):
    response = add(client, headers, TOMORROW, category="other", title="  Dentist  ", start="10:00", duration_minutes=60)
    assert response.status_code == 201, response.text
    plan = response.json()
    assert (plan["source"], plan["revision"], plan["plan_date"]) == ("manual", 1, TOMORROW)
    assert [(i["title"], i["start"], i["end"], i["manual"]) for i in plan["items"]] == [
        ("Dentist", "10:00", "11:00", True)
    ]
    assert plan_for(client, headers, TOMORROW).json() == plan
    later = add(client, headers, TOMORROW, category="fitness", title="Run", start="07:30", duration_minutes=30)
    assert later.status_code == 200
    assert [item["title"] for item in later.json()["items"]] == ["Run", "Dentist"]


def test_a_study_block_takes_its_subjects_name(client, headers, fixed_clock):
    subject = client.post("/api/study/subjects", headers=headers, json={"name": "DBMS"}).json()
    response = add(
        client, headers, TOMORROW, category="study", subject_id=subject["id"], start="18:00", duration_minutes=50
    )
    assert response.status_code == 201, response.text
    item = response.json()["items"][0]
    assert (item["title"], item["subject_id"], item["end"]) == ("DBMS", subject["id"], "18:50")


def test_an_overlap_is_refused_and_names_what_it_overlaps(client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    block = plan["items"][0]
    response = add(client, headers, category="break", title="Coffee", start=block["start"], duration_minutes=15)
    assert response.status_code == 409
    error = response.json()["error"]
    assert error["code"] == "plan_item_conflict"
    assert block["title"] in error["message"] and "Nothing was moved" in error["message"]
    assert error["details"][0] == {
        "kind": "plan_block",
        "title": block["title"],
        "start": block["start"],
        "end": block["end"],
    }
    assert plan_for(client, headers).json()["revision"] == plan["revision"]


def test_a_fixed_commitment_is_a_conflict_too(client, headers, fixed_clock):
    client.post(
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
    )
    response = add(client, headers, TOMORROW, category="other", title="Call", start="10:30", duration_minutes=60)
    assert response.status_code == 409
    assert response.json()["error"]["details"] == [
        {"kind": "commitment", "title": "Lab", "start": "10:00", "end": "11:00"}
    ]
    assert plan_for(client, headers, TOMORROW).status_code == 404
    # Back to back is fine.
    assert (
        add(client, headers, TOMORROW, category="other", title="Call", start="11:00", duration_minutes=30).status_code
        == 201
    )


@pytest.mark.parametrize(
    ("day", "body", "message"),
    [
        (TODAY, {"category": "other", "title": "x", "start": "08:30", "duration_minutes": 30}, "already passed"),
        (
            "2026-10-03",
            {"category": "other", "title": "x", "start": "10:00", "duration_minutes": 30},
            "today or a later",
        ),
        ("2026-12-31", {"category": "other", "title": "x", "start": "10:00", "duration_minutes": 30}, "60 days"),
        (TOMORROW, {"category": "other", "title": "x", "start": "23:30", "duration_minutes": 60}, "23:59"),
    ],
)
def test_impossible_times_are_refused(client, headers, fixed_clock, day, body, message):
    response = add(client, headers, day, **body)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "plan_item_invalid"
    assert message in response.json()["error"]["message"]


@pytest.mark.parametrize(
    "body",
    [
        {"category": "other", "start": "10:00", "duration_minutes": 30},
        {"category": "other", "title": "x", "start": "10:00", "duration_minutes": 3},
        {"category": "other", "title": "x", "start": "25:00", "duration_minutes": 30},
        {"category": "task", "start": "10:00", "duration_minutes": 30},
        {
            "category": "other",
            "title": "x",
            "start": "10:00",
            "duration_minutes": 30,
            "task_id": "00000000-0000-0000-0000-000000000001",
        },
        {"category": "other", "title": "x", "start": "10:00", "duration_minutes": 30, "user_id": "x"},
    ],
)
def test_malformed_blocks_are_validation_errors(client, headers, fixed_clock, body):
    response = add(client, headers, TOMORROW, **body)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_a_stale_view_is_told_to_refresh(client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    first = add(
        client, headers, category="other", title="A", start="22:00", duration_minutes=15, base_revision=plan["revision"]
    )
    assert first.status_code == 200
    again = add(
        client, headers, category="other", title="B", start="22:30", duration_minutes=15, base_revision=plan["revision"]
    )
    assert again.status_code == 409
    assert again.json()["error"]["code"] == "plan_stale"


def test_a_task_already_planned_is_not_planned_twice(client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    planned = next(item for item in plan["items"] if item["task_id"])
    response = add(client, headers, category="task", task_id=planned["task_id"], start="22:30", duration_minutes=30)
    assert response.status_code == 422
    assert "already in this plan" in response.json()["error"]["message"]


def test_other_peoples_records_and_plans_stay_private(client, headers, other_headers, fixed_clock):
    task = new_task(client, headers)
    subject = client.post("/api/study/subjects", headers=headers, json={"name": "Maths"}).json()
    as_other = add(
        client, other_headers, TOMORROW, category="task", task_id=task["id"], start="10:00", duration_minutes=30
    )
    assert as_other.status_code == 404
    as_other = add(
        client, other_headers, TOMORROW, category="study", subject_id=subject["id"], start="10:00", duration_minutes=30
    )
    assert as_other.status_code == 404
    assert (
        add(client, headers, TOMORROW, category="other", title="Mine", start="10:00", duration_minutes=30).status_code
        == 201
    )
    assert plan_for(client, other_headers, TOMORROW).status_code == 404
    assert (
        add(
            client,
            headers,
            TOMORROW,
            category="other",
            title="Mine",
            start="12:00",
            duration_minutes=30,
            base_revision=1,
        ).status_code
        == 200
    )


def test_a_manual_block_can_be_checked_off(client, headers, fixed_clock):
    task = new_task(client, headers)
    plan = add(client, headers, category="task", task_id=task["id"], start="10:00", duration_minutes=30).json()
    key = plan["items"][0]["item_key"]
    response = client.put(f"/api/ai/daily-plan/{TODAY}/items/{key}/outcome", headers=headers, json={"status": "done"})
    assert response.status_code == 200, response.text
    assert response.json()["items"][0]["outcome"] == "done"
    assert client.get(f"/api/tasks/{task['id']}", headers=headers).json()["status"] == "done"


def test_generation_plans_around_manual_blocks_and_keeps_them(client, headers, fixed_clock):
    new_task(client, headers, "Essay", 60)
    manual = add(client, headers, category="other", title="Lunch with Sam", start="10:00", duration_minutes=180).json()
    kept = manual["items"][0]
    generated = client.post("/api/ai/daily-plan", headers=headers, json={"regenerate": True})
    assert generated.status_code == 201, generated.text
    items = generated.json()["items"]
    assert next(item for item in items if item["manual"]) == kept
    others = [item for item in items if not item["manual"]]
    assert others, "the planner still plans the rest of the day"
    assert all(item["end"] <= "10:00" or item["start"] >= "13:00" for item in others)


def test_replanning_never_moves_a_manual_block(client, headers, fixed_clock):
    plan = setup_day(client, headers, fixed_clock)
    kept = next(
        item
        for item in add(
            client,
            headers,
            category="recovery",
            title="Nap",
            start="22:00",
            duration_minutes=30,
            base_revision=plan["revision"],
        ).json()["items"]
        if item["manual"]
    )
    proposal = make_proposal(client, headers)
    assert proposal.status_code == 201, proposal.text
    assert all(item["item_key"] != kept["item_key"] for item in proposal.json()["schedule"])
    applied = client.post(f"/api/ai/replan/proposals/{proposal.json()['id']}/apply", headers=headers)
    assert applied.status_code == 200, applied.text
    assert next(item for item in applied.json()["items"] if item["manual"]) == kept
