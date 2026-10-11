"""Long-term goals: measurable or completion-only, owner-scoped, completion is explicit."""

from datetime import UTC, datetime

from tests.conftest import auth_headers, register

MEASURABLE = {"title": "Lift 30 kg", "category": "activity", "target_value": 30, "current_value": 22.5, "unit": "kg"}


def test_create_list_get_measurable_and_completion_only(client, headers):
    measurable = client.post("/api/goals", json={**MEASURABLE, "deadline": "2026-12-31"}, headers=headers)
    assert measurable.status_code == 201, measurable.text
    body = measurable.json()
    assert body["current_value"] == 22.5 and body["target_value"] == 30 and body["unit"] == "kg"
    assert body["completed"] is False and body["completed_at"] is None

    simple = client.post("/api/goals", json={"title": "Read Dune", "category": "habits"}, headers=headers)
    assert simple.status_code == 201
    assert simple.json()["target_value"] is None and simple.json()["unit"] is None

    starts_at_zero = client.post(
        "/api/goals", json={"title": "Run", "category": "activity", "target_value": 100, "unit": "km"}, headers=headers
    )
    assert starts_at_zero.json()["current_value"] == 0

    listed = client.get("/api/goals", headers=headers).json()
    assert [goal["title"] for goal in listed][0] == "Lift 30 kg"  # nearest deadline first
    assert {goal["title"] for goal in listed} == {"Lift 30 kg", "Read Dune", "Run"}
    assert client.get(f"/api/goals/{body['id']}", headers=headers).json()["title"] == "Lift 30 kg"


def test_measurement_rules_are_enforced(client, headers):
    for bad in (
        {"title": "x", "category": "habits", "unit": "kg"},
        {"title": "x", "category": "habits", "current_value": 3},
        {"title": "x", "category": "activity", "target_value": 0, "unit": "kg"},
        {"title": "x", "category": "activity", "target_value": 10, "current_value": -1, "unit": "kg"},
        {"title": "x", "category": "activity", "target_value": 10},
        {"title": "x", "category": "money"},
        {"title": " ", "category": "habits"},
        {"title": "x", "category": "habits", "user_id": "someone"},
    ):
        assert client.post("/api/goals", json=bad, headers=headers).status_code == 422, bad

    goal = client.post("/api/goals", json=MEASURABLE, headers=headers).json()
    # Dropping the unit alone would leave a half-measured goal.
    assert client.patch(f"/api/goals/{goal['id']}", json={"unit": None}, headers=headers).status_code == 422
    assert client.patch(f"/api/goals/{goal['id']}", json={"title": None}, headers=headers).status_code == 422
    # Clearing all three makes it completion-only.
    cleared = client.patch(
        f"/api/goals/{goal['id']}",
        json={"target_value": None, "current_value": None, "unit": None},
        headers=headers,
    )
    assert cleared.status_code == 200
    assert cleared.json()["target_value"] is None and cleared.json()["unit"] is None


def test_completion_is_explicit_and_keeps_values(client, headers, clock):
    goal = client.post(
        "/api/goals", json={**MEASURABLE, "current_value": 35}, headers=headers
    ).json()  # past target, still open
    assert goal["completed"] is False

    clock.set(datetime(2026, 3, 11, 9, tzinfo=UTC))
    done = client.patch(f"/api/goals/{goal['id']}", json={"completed": True}, headers=headers).json()
    assert done["completed"] is True
    assert done["completed_at"].startswith("2026-03-11T09:00:00")
    assert done["current_value"] == 35

    reopened = client.patch(f"/api/goals/{goal['id']}", json={"completed": False}, headers=headers).json()
    assert reopened["completed"] is False and reopened["completed_at"] is None
    assert reopened["current_value"] == 35

    progress = client.patch(f"/api/goals/{goal['id']}", json={"current_value": 36}, headers=headers).json()
    assert progress["current_value"] == 36 and progress["completed"] is False


def test_goals_are_private(client, headers, other_headers):
    goal = client.post("/api/goals", json=MEASURABLE, headers=headers).json()
    assert client.get("/api/goals", headers=other_headers).json() == []
    for call in (
        lambda: client.get(f"/api/goals/{goal['id']}", headers=other_headers),
        lambda: client.patch(f"/api/goals/{goal['id']}", json={"completed": True}, headers=other_headers),
        lambda: client.delete(f"/api/goals/{goal['id']}", headers=other_headers),
    ):
        assert call().status_code == 404
    assert client.get("/api/goals").status_code == 401
    assert client.get(f"/api/goals/{goal['id']}", headers=headers).json()["completed"] is False


def test_delete_and_account_deletion_cascade(client):
    payload = register(client)
    headers = auth_headers(payload)
    goal = client.post("/api/goals", json=MEASURABLE, headers=headers).json()
    assert client.delete(f"/api/goals/{goal['id']}", headers=headers).status_code == 204
    assert client.get(f"/api/goals/{goal['id']}", headers=headers).status_code == 404
    client.post("/api/goals", json=MEASURABLE, headers=headers)
    export = client.get("/api/account/export", headers=headers).json()
    assert [row["title"] for row in export["goals"]] == ["Lift 30 kg"]
    deleted = client.post("/api/auth/delete-account", json={"password": "correct-horse-battery"}, headers=headers)
    assert deleted.status_code in (200, 204)
