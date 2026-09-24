from datetime import UTC, datetime, timedelta

import jwt

from tests.conftest import auth_headers, register


def test_register_returns_token_and_profile(client):
    data = register(client, email="  Asha@Example.COM ", display_name="  Asha ", timezone="Asia/Kolkata")
    assert data["token_type"] == "bearer"
    assert data["expires_in"] > 0
    assert data["user"]["email"] == "asha@example.com"
    assert data["user"]["profile"]["display_name"] == "Asha"
    assert data["user"]["profile"]["timezone"] == "Asia/Kolkata"
    assert "password" not in str(data)


def test_register_rejects_duplicate_email_case_insensitive(client):
    register(client, email="dup@example.com")
    response = client.post(
        "/api/auth/register",
        json={
            "email": "DUP@example.com",
            "password": "another-password",
            "display_name": "X",
        },
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "conflict"


def test_register_validates_input(client):
    response = client.post(
        "/api/auth/register",
        json={
            "email": "not-an-email",
            "password": "short",
            "display_name": "",
            "timezone": "Mars/Base",
        },
    )
    assert response.status_code == 422
    fields = {d["field"] for d in response.json()["error"]["details"]}
    assert {"body.email", "body.password", "body.display_name", "body.timezone"} <= fields


def test_register_rejects_unknown_fields(client):
    response = client.post(
        "/api/auth/register",
        json={
            "email": "a@b.co",
            "password": "long-enough-pw",
            "display_name": "A",
            "is_admin": True,
        },
    )
    assert response.status_code == 422


def test_login_success_and_me(client):
    register(client, email="login@example.com", password="right-password-1")
    response = client.post("/api/auth/login", json={"email": "Login@Example.com", "password": "right-password-1"})
    assert response.status_code == 200
    me = client.get("/api/auth/me", headers=auth_headers(response.json()))
    assert me.status_code == 200
    assert me.json()["email"] == "login@example.com"


def test_login_wrong_password_and_unknown_email_look_the_same(client):
    register(client, email="known@example.com", password="right-password-1")
    wrong = client.post("/api/auth/login", json={"email": "known@example.com", "password": "nope-nope"})
    unknown = client.post("/api/auth/login", json={"email": "ghost@example.com", "password": "nope-nope"})
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json()["error"]["message"] == unknown.json()["error"]["message"]


def test_protected_route_requires_token(client):
    response = client.get("/api/auth/me")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.json()["error"]["code"] == "unauthorized"


def test_rejects_garbage_expired_and_foreign_tokens(client, user):
    assert client.get("/api/auth/me", headers={"Authorization": "Bearer not.a.jwt"}).status_code == 401

    now = datetime.now(UTC)
    sub = user["user"]["id"]
    secret = "test-secret-that-is-long-enough-for-hs256-signing"
    expired = jwt.encode(
        {"sub": sub, "type": "access", "iat": now - timedelta(hours=2), "exp": now - timedelta(hours=1)},
        secret,
        algorithm="HS256",
    )
    assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {expired}"}).status_code == 401

    forged = jwt.encode(
        {"sub": sub, "type": "access", "iat": now, "exp": now + timedelta(hours=1)},
        "some-other-secret-that-is-also-long-enough",
        algorithm="HS256",
    )
    assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {forged}"}).status_code == 401


def test_login_is_rate_limited(client, monkeypatch):
    from app.core.config import get_settings

    register(client, email="limited@example.com")
    monkeypatch.setattr(get_settings(), "auth_rate_limit_per_minute", 3)
    body = {"email": "limited@example.com", "password": "wrong-password"}
    codes = [client.post("/api/auth/login", json=body).status_code for _ in range(4)]
    assert codes == [401, 401, 401, 429]
    last = client.post("/api/auth/login", json=body)
    assert last.status_code == 429
    assert int(last.headers["retry-after"]) >= 1


def test_delete_account_requires_password_and_removes_data(client, headers):
    client.post("/api/tasks", json={"title": "Private task"}, headers=headers)
    bad = client.post("/api/auth/delete-account", json={"password": "wrong"}, headers=headers)
    assert bad.status_code == 403
    ok = client.post("/api/auth/delete-account", json={"password": "correct-horse-battery"}, headers=headers)
    assert ok.status_code == 204
    assert client.get("/api/auth/me", headers=headers).status_code == 401


def test_profile_update_and_validation(client, headers):
    response = client.patch(
        "/api/profile",
        json={
            "daily_study_goal_minutes": 180,
            "timezone": "Europe/London",
            "preferred_workout_time": "morning",
        },
        headers=headers,
    )
    assert response.status_code == 200
    assert response.json()["daily_study_goal_minutes"] == 180
    assert response.json()["timezone"] == "Europe/London"

    assert client.patch("/api/profile", json={"display_name": None}, headers=headers).status_code == 422
    assert client.patch("/api/profile", json={"daily_step_goal": -5}, headers=headers).status_code == 422
    assert client.patch("/api/profile", json={"timezone": "Nowhere/Land"}, headers=headers).status_code == 422


def test_legacy_browser_timezone_is_normalized(client):
    data = register(client, timezone="Asia/Calcutta")
    assert data["user"]["profile"]["timezone"] == "Asia/Kolkata"
    for bad in ("../../etc/passwd", "/etc/localtime", "Mars/Base"):
        response = client.post(
            "/api/auth/register",
            json={"email": "tz@example.com", "password": "long-enough-pw", "display_name": "T", "timezone": bad},
        )
        assert response.status_code == 422, bad
