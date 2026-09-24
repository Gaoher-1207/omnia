from datetime import date, timedelta


def _subject(client, headers, name="Physics"):
    response = client.post("/api/study/subjects", json={"name": name, "color": "#3366ff"}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def test_subjects_crud_and_duplicate_name(client, headers):
    physics = _subject(client, headers)
    assert client.post("/api/study/subjects", json={"name": "Physics"}, headers=headers).status_code == 409
    assert (
        client.post("/api/study/subjects", json={"name": "Maths", "color": "blue"}, headers=headers).status_code == 422
    )
    renamed = client.patch(f"/api/study/subjects/{physics['id']}", json={"name": "Physics II"}, headers=headers)
    assert renamed.json()["name"] == "Physics II"
    assert [s["name"] for s in client.get("/api/study/subjects", headers=headers).json()] == ["Physics II"]


def test_same_subject_name_allowed_for_different_users(client, headers, other_headers):
    _subject(client, headers, "Chemistry")
    _subject(client, other_headers, "Chemistry")


def test_exams_list_upcoming_with_days_left(client, headers):
    subject = _subject(client, headers)
    today = date.today()
    client.post(
        "/api/study/exams",
        json={
            "subject_id": subject["id"],
            "title": "Midterm",
            "exam_date": (today + timedelta(days=8)).isoformat(),
        },
        headers=headers,
    )
    client.post(
        "/api/study/exams",
        json={
            "subject_id": subject["id"],
            "title": "Old quiz",
            "exam_date": (today - timedelta(days=3)).isoformat(),
        },
        headers=headers,
    )
    upcoming = client.get("/api/study/exams", headers=headers).json()
    assert [(e["title"], e["days_left"]) for e in upcoming] == [("Midterm", 8)]
    assert upcoming[0]["subject"]["name"] == "Physics"
    assert len(client.get("/api/study/exams?include_past=true", headers=headers).json()) == 2


def test_cannot_attach_to_someone_elses_subject(client, headers, other_headers):
    theirs = _subject(client, other_headers, "Their subject")
    exam = client.post(
        "/api/study/exams",
        json={
            "subject_id": theirs["id"],
            "title": "Sneaky",
            "exam_date": date.today().isoformat(),
        },
        headers=headers,
    )
    assert exam.status_code == 404
    item = client.post("/api/study/backlog", json={"subject_id": theirs["id"], "title": "x"}, headers=headers)
    assert item.status_code == 404
    session = client.post(
        "/api/study/sessions", json={"subject_id": theirs["id"], "duration_minutes": 30}, headers=headers
    )
    assert session.status_code == 404
    assert client.delete(f"/api/study/subjects/{theirs['id']}", headers=headers).status_code == 404


def test_backlog_and_sessions_flow(client, headers):
    subject = _subject(client, headers)
    item = client.post(
        "/api/study/backlog",
        json={
            "subject_id": subject["id"],
            "title": "Chapter 4: Waves",
            "estimated_minutes": 90,
        },
        headers=headers,
    ).json()
    assert item["status"] == "pending" and item["kind"] == "backlog"

    session = client.post(
        "/api/study/sessions",
        json={
            "backlog_item_id": item["id"],
            "duration_minutes": 45,
            "complete_backlog_item": True,
        },
        headers=headers,
    )
    assert session.status_code == 201
    assert session.json()["subject"]["id"] == subject["id"]
    assert session.json()["session_date"] == date.today().isoformat()

    backlog = client.get("/api/study/backlog", headers=headers).json()
    assert backlog[0]["status"] == "done" and backlog[0]["completed_at"]
    assert client.get("/api/study/backlog?status=pending", headers=headers).json() == []

    sessions = client.get("/api/study/sessions", headers=headers).json()
    assert len(sessions) == 1


def test_session_validation(client, headers):
    tomorrow = (date.today() + timedelta(days=1)).isoformat()
    assert client.post("/api/study/sessions", json={"duration_minutes": 0}, headers=headers).status_code == 422
    assert client.post("/api/study/sessions", json={"duration_minutes": 721}, headers=headers).status_code == 422
    future = client.post(
        "/api/study/sessions", json={"duration_minutes": 30, "session_date": tomorrow}, headers=headers
    )
    assert future.status_code == 422
    assert future.json()["error"]["details"][0]["field"] == "body.session_date"

    a, b = _subject(client, headers, "A"), _subject(client, headers, "B")
    item = client.post("/api/study/backlog", json={"subject_id": a["id"], "title": "t"}, headers=headers).json()
    mismatch = client.post(
        "/api/study/sessions",
        json={
            "duration_minutes": 30,
            "backlog_item_id": item["id"],
            "subject_id": b["id"],
        },
        headers=headers,
    )
    assert mismatch.status_code == 422


def test_session_range_validation(client, headers):
    assert client.get("/api/study/sessions?from=2026-05-10&to=2026-05-01", headers=headers).status_code == 400


def test_deleting_subject_cascades_but_keeps_sessions(client, headers):
    subject = _subject(client, headers)
    client.post("/api/study/backlog", json={"subject_id": subject["id"], "title": "t"}, headers=headers)
    client.post(
        "/api/study/exams",
        json={
            "subject_id": subject["id"],
            "title": "e",
            "exam_date": date.today().isoformat(),
        },
        headers=headers,
    )
    client.post("/api/study/sessions", json={"subject_id": subject["id"], "duration_minutes": 20}, headers=headers)
    assert client.delete(f"/api/study/subjects/{subject['id']}", headers=headers).status_code == 204
    assert client.get("/api/study/backlog", headers=headers).json() == []
    assert client.get("/api/study/exams", headers=headers).json() == []
    sessions = client.get("/api/study/sessions", headers=headers).json()
    assert len(sessions) == 1 and sessions[0]["subject"] is None


def test_study_plan_endpoint(client, headers):
    client.patch("/api/profile", json={"daily_study_goal_minutes": 120}, headers=headers)
    subject = _subject(client, headers)
    client.post(
        "/api/study/exams",
        json={
            "subject_id": subject["id"],
            "title": "Final",
            "exam_date": (date.today() + timedelta(days=3)).isoformat(),
        },
        headers=headers,
    )
    client.post(
        "/api/study/backlog",
        json={
            "subject_id": subject["id"],
            "title": "Optics",
            "estimated_minutes": 90,
        },
        headers=headers,
    )
    client.post("/api/study/sessions", json={"subject_id": subject["id"], "duration_minutes": 30}, headers=headers)

    plan = client.get("/api/study/plan?days=5", headers=headers).json()
    today = plan["days"][0]
    assert today["available_minutes"] == 90
    assert today["blocks"][0]["title"] == "Optics"
    assert today["blocks"][0]["reason"] == "Exam in 3 days"
    assert plan["days"][3]["exams"][0]["title"] == "Final"
    assert plan["unscheduled_minutes"] == 0
    assert client.get("/api/study/plan?days=0", headers=headers).status_code == 422


def test_study_plan_empty_state(client, headers):
    plan = client.get("/api/study/plan", headers=headers).json()
    assert len(plan["days"]) == 7
    assert all(d["blocks"] == [] for d in plan["days"])
    assert plan["warnings"] == []
