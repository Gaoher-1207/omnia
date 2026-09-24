from datetime import UTC, date, datetime, timedelta

import pytest

from app.modules.progress.streaks import DayFacts, current_streak, longest_streak


@pytest.fixture
def freeze(monkeypatch):
    def _freeze(moment: datetime):
        monkeypatch.setattr("app.core.time.utcnow", lambda: moment)
        monkeypatch.setattr("app.modules.tasks.service.utcnow", lambda: moment)
        monkeypatch.setattr("app.modules.study.service.utcnow", lambda: moment)

    return _freeze


# ---- pure streak rules


def test_current_streak_counts_back_from_today_or_yesterday():
    today = date(2026, 3, 10)
    days = {today - timedelta(days=n) for n in range(3)}
    assert current_streak(days, today) == 3
    assert current_streak(days - {today}, today) == 2
    assert current_streak({today - timedelta(days=2)}, today) == 0
    assert current_streak(set(), today) == 0


def test_longest_streak():
    base = date(2026, 1, 1)
    days = {
        base,
        base + timedelta(days=1),
        base + timedelta(days=5),
        base + timedelta(days=6),
        base + timedelta(days=7),
    }
    assert longest_streak(days) == 3
    assert longest_streak(set()) == 0


def test_balance_needs_two_areas_and_fitness_counts_steps():
    d = date(2026, 3, 1)
    assert DayFacts(d, study_minutes=30, tasks_completed=1).balanced(8000)
    assert not DayFacts(d, study_minutes=30).balanced(8000)
    assert DayFacts(d, study_minutes=30, steps=8000).balanced(8000)
    assert not DayFacts(d, steps=5000).fitness_active(8000)
    assert not DayFacts(d, steps=0).fitness_active(0)


# ---- activity endpoints


def test_activity_upsert_is_idempotent(client, headers):
    today = date.today().isoformat()
    body = {"steps": 6240, "workout_done": True, "workout_minutes": 40, "workout_type": "Run"}
    first = client.put(f"/api/activity/{today}", json=body, headers=headers)
    second = client.put(f"/api/activity/{today}", json=body, headers=headers)
    assert first.status_code == second.status_code == 200
    assert first.json()["id"] == second.json()["id"]
    assert client.get(f"/api/activity/{today}", headers=headers).json()["steps"] == 6240


def test_activity_clears_workout_details_when_not_done(client, headers):
    today = date.today().isoformat()
    body = {"steps": 100, "workout_done": False, "workout_minutes": 40, "workout_type": "Run"}
    saved = client.put(f"/api/activity/{today}", json=body, headers=headers).json()
    assert saved["workout_minutes"] == 0 and saved["workout_type"] is None


def test_activity_validation_and_future_dates(client, headers):
    today = date.today()
    assert client.put(f"/api/activity/{today}", json={"steps": -1}, headers=headers).status_code == 422
    assert client.put(f"/api/activity/{today}", json={"steps": 300000}, headers=headers).status_code == 422
    future = client.put(f"/api/activity/{today + timedelta(days=2)}", json={"steps": 10}, headers=headers)
    assert future.status_code == 422
    assert client.put("/api/activity/not-a-date", json={"steps": 10}, headers=headers).status_code == 422


def test_activity_range_fills_missing_days(client, headers):
    today = date.today()
    client.put(f"/api/activity/{today}", json={"steps": 500}, headers=headers)
    data = client.get(f"/api/activity?from={today - timedelta(days=6)}&to={today}", headers=headers).json()
    assert len(data["days"]) == 7
    assert data["days"][-1]["steps"] == 500 and data["days"][0]["steps"] == 0
    assert data["step_goal"] == 8000
    too_long = client.get(f"/api/activity?from={today - timedelta(days=200)}&to={today}", headers=headers)
    assert too_long.status_code == 422


def test_activity_is_private(client, headers, other_headers):
    today = date.today().isoformat()
    client.put(f"/api/activity/{today}", json={"steps": 999}, headers=headers)
    assert client.get(f"/api/activity/{today}", headers=other_headers).json()["steps"] == 0


# ---- progress endpoint


def test_progress_streaks_end_to_end(client, headers, freeze):
    today = date(2026, 3, 10)
    for offset in (3, 2, 1):
        day = today - timedelta(days=offset)
        freeze(datetime(day.year, day.month, day.day, 12, tzinfo=UTC))
        client.post("/api/study/sessions", json={"duration_minutes": 30}, headers=headers)
        task = client.post("/api/tasks", json={"title": f"t{offset}"}, headers=headers).json()
        client.patch(f"/api/tasks/{task['id']}", json={"status": "done"}, headers=headers)
        client.put(f"/api/activity/{day}", json={"steps": 9000}, headers=headers)

    freeze(datetime(2026, 3, 10, 8, tzinfo=UTC))
    progress = client.get("/api/progress", headers=headers).json()
    streaks = progress["streaks"]
    assert streaks["study"] == {"current": 3, "longest": 3, "active_today": False}
    assert streaks["tasks"]["current"] == 3
    assert streaks["fitness"]["current"] == 3
    assert streaks["balance"]["current"] == 3
    assert len(progress["history"]) == 14
    assert progress["history"][-1]["date"] == "2026-03-10"
    assert progress["history"][-2]["balanced"] is True


def test_task_completion_counts_on_users_local_day(client, freeze):
    from tests.conftest import auth_headers, register

    headers = auth_headers(register(client, timezone="Asia/Kolkata"))
    freeze(datetime(2026, 3, 9, 20, 0, tzinfo=UTC))  # 01:30 on 10 March in India
    task = client.post("/api/tasks", json={"title": "late night"}, headers=headers).json()
    client.patch(f"/api/tasks/{task['id']}", json={"status": "done"}, headers=headers)
    progress = client.get("/api/progress", headers=headers).json()
    assert progress["date"] == "2026-03-10"
    assert progress["history"][-1]["tasks_completed"] == 1
    assert progress["streaks"]["tasks"]["active_today"] is True
