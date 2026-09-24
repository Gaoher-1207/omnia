import json
import logging
from datetime import date, timedelta

from tests.conftest import auth_headers, register

TODAY = date.today()


def test_change_password_revokes_old_tokens(client):
    data = register(client, email="pw@example.com", password="old-password-1")
    old = auth_headers(data)
    wrong = client.post(
        "/api/auth/change-password", json={"current_password": "nope", "new_password": "new-password-1"}, headers=old
    )
    assert wrong.status_code == 403
    short = client.post(
        "/api/auth/change-password", json={"current_password": "old-password-1", "new_password": "short"}, headers=old
    )
    assert short.status_code == 422
    changed = client.post(
        "/api/auth/change-password",
        json={"current_password": "old-password-1", "new_password": "new-password-1"},
        headers=old,
    )
    assert changed.status_code == 200
    assert client.get("/api/auth/me", headers=old).status_code == 401, "old token revoked"
    assert client.get("/api/auth/me", headers=auth_headers(changed.json())).status_code == 200
    login_old = client.post("/api/auth/login", json={"email": "pw@example.com", "password": "old-password-1"})
    assert login_old.status_code == 401
    assert (
        client.post("/api/auth/login", json={"email": "pw@example.com", "password": "new-password-1"}).status_code
        == 200
    )


def test_logout_all(client, headers):
    assert client.post("/api/auth/logout-all", headers=headers).status_code == 204
    assert client.get("/api/auth/me", headers=headers).status_code == 401


def test_calendar_feed_link_lifecycle(client, headers, other_headers, caplog):
    subject = client.post("/api/study/subjects", json={"name": "Physics"}, headers=headers).json()
    client.post(
        "/api/study/exams",
        json={
            "subject_id": subject["id"],
            "title": "Final, part 1",
            "exam_date": (TODAY + timedelta(days=5)).isoformat(),
        },
        headers=headers,
    )
    client.post(
        "/api/tasks",
        json={"title": "Lab report", "due_date": TODAY.isoformat(), "due_time": "17:00", "estimated_minutes": 45},
        headers=headers,
    )
    client.post("/api/tasks", json={"title": "Undated"}, headers=headers)
    client.post("/api/ai/daily-plan", json={}, headers=headers)

    url = client.post("/api/integrations/calendar", headers=headers).json()["url"]
    path = url[url.index("/api/") :]
    with caplog.at_level(logging.INFO, logger="omnia.access"):
        feed = client.get(path)
    assert feed.status_code == 200 and feed.headers["content-type"].startswith("text/calendar")
    body = feed.text
    assert body.startswith("BEGIN:VCALENDAR") and body.rstrip().endswith("END:VCALENDAR")
    assert "SUMMARY:Exam: Final\\, part 1" in body
    assert "SUMMARY:Lab report" in body and "T170000" in body and "T174500" in body
    assert "Undated" not in body
    token = path.rsplit("/", 1)[1].removesuffix(".ics")
    assert token not in caplog.text, "secret calendar token must not be logged"

    new_url = client.post("/api/integrations/calendar", headers=headers).json()["url"]
    assert client.get(path).status_code == 404, "rotating the link kills the old one"
    new_path = new_url[new_url.index("/api/") :]
    assert client.get(new_path).status_code == 200
    assert client.delete("/api/integrations/calendar", headers=other_headers).status_code == 404
    assert client.delete("/api/integrations/calendar", headers=headers).status_code == 204
    assert client.get(new_path).status_code == 404
    assert client.get("/api/integrations/calendar/guess.ics").status_code == 404


def test_export_contains_only_my_data(client, headers, other_headers, user):
    client.post("/api/tasks", json={"title": "Mine"}, headers=headers)
    client.post("/api/tasks", json={"title": "Theirs"}, headers=other_headers)
    client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 420}, headers=headers)
    response = client.get("/api/account/export", headers=headers)
    assert response.status_code == 200
    assert "attachment" in response.headers["content-disposition"]
    data = json.loads(response.content)
    assert data["account"]["email"] == user["user"]["email"]
    assert [t["title"] for t in data["tasks"]] == ["Mine"]
    assert data["sleep"][0]["duration_minutes"] == 420
    assert "password_hash" not in response.text
    assert client.get("/api/account/export").status_code == 401


def test_oversized_requests_rejected(client, headers):
    huge = "x" * (9 * 1024 * 1024)
    response = client.post(
        "/api/tasks", content=json.dumps({"title": huge}), headers={**headers, "Content-Type": "application/json"}
    )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "payload_too_large"
