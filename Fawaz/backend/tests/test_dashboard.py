from datetime import date, timedelta


def test_dashboard_empty_state(client, headers, user):
    data = client.get("/api/dashboard", headers=headers).json()
    assert data["display_name"] == user["user"]["profile"]["display_name"]
    assert data["greeting"] in {"morning", "afternoon", "evening"}
    assert data["today"] == {
        "study_minutes": 0,
        "study_goal_minutes": 240,
        "tasks_completed": 0,
        "task_goal": 5,
        "steps": 0,
        "step_goal": 8000,
        "workout_status": "pending",
        "workout_minutes": 0,
        "sleep_minutes": None,
        "sleep_goal_minutes": 480,
        "calories": 0,
        "calorie_goal": 2000,
    }
    assert data["next_exam"] is None
    assert data["upcoming_tasks"] == []
    assert data["study_today"] == []
    assert data["ai_plan"] is None
    assert data["streaks"]["balance"]["current"] == 0


def test_dashboard_reflects_today(client, headers):
    today = date.today()
    subject = client.post("/api/study/subjects", json={"name": "Biology"}, headers=headers).json()
    client.post(
        "/api/study/exams",
        json={
            "subject_id": subject["id"],
            "title": "Unit test",
            "exam_date": (today + timedelta(days=8)).isoformat(),
        },
        headers=headers,
    )
    client.post("/api/study/backlog", json={"subject_id": subject["id"], "title": "Cells"}, headers=headers)
    client.post("/api/study/sessions", json={"subject_id": subject["id"], "duration_minutes": 150}, headers=headers)
    for n in range(3):
        client.post("/api/tasks", json={"title": f"open {n}"}, headers=headers)
    done = client.post("/api/tasks", json={"title": "done"}, headers=headers).json()
    client.patch(f"/api/tasks/{done['id']}", json={"status": "done"}, headers=headers)
    client.put(f"/api/activity/{today}", json={"steps": 6240, "workout_done": False}, headers=headers)
    client.post("/api/ai/daily-plan", json={}, headers=headers)

    data = client.get("/api/dashboard", headers=headers).json()
    assert data["today"]["study_minutes"] == 150
    assert data["today"]["tasks_completed"] == 1
    assert data["today"]["steps"] == 6240
    assert data["next_exam"]["days_left"] == 8 and data["next_exam"]["subject_name"] == "Biology"
    assert len(data["upcoming_tasks"]) == 3
    assert data["study_today"][0]["title"] == "Cells"
    assert data["ai_plan"] is not None


def test_dashboard_requires_auth(client):
    assert client.get("/api/dashboard").status_code == 401
