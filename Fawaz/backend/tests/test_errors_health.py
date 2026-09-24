from fastapi import APIRouter
from fastapi.testclient import TestClient


def test_health_and_ready(client):
    assert client.get("/api/health").json() == {"status": "ok"}
    assert client.get("/api/health/ready").json() == {"status": "ok", "database": "ok"}


def test_request_id_and_security_headers(client):
    response = client.get("/api/health", headers={"X-Request-ID": "abc123"})
    assert response.headers["x-request-id"] == "abc123"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert client.get("/api/health").headers["x-request-id"]


def test_unknown_route_uses_error_envelope(client):
    response = client.get("/api/nope")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_validation_errors_do_not_echo_input(client, headers):
    secret_looking = "SUPER-SECRET-VALUE-" + "x" * 300
    response = client.post("/api/tasks", json={"title": secret_looking}, headers=headers)
    assert response.status_code == 422
    assert "SUPER-SECRET" not in response.text


def test_malformed_json(client, headers):
    response = client.post("/api/tasks", content="{not json", headers={**headers, "Content-Type": "application/json"})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_unhandled_errors_are_generic(app):
    boom = APIRouter()

    @boom.get("/api/boom")
    def _boom():
        raise RuntimeError("database password is hunter2")

    app.include_router(boom)
    with TestClient(app, raise_server_exceptions=False) as c:
        response = c.get("/api/boom")
    assert response.status_code == 500
    body = response.json()
    assert body["error"]["code"] == "internal_error"
    assert "hunter2" not in response.text
    assert body["error"]["request_id"]


def test_cors_allows_any_localhost_port_only_in_development(monkeypatch):
    from fastapi.testclient import TestClient

    from app.core.config import get_settings
    from app.main import create_app

    def preflight(env: str, origin: str):
        monkeypatch.setenv("APP_ENV", env)
        get_settings.cache_clear()
        try:
            client = TestClient(create_app())
            return client.options(
                "/api/health", headers={"Origin": origin, "Access-Control-Request-Method": "GET"}
            ).headers.get("access-control-allow-origin")
        finally:
            get_settings.cache_clear()

    assert preflight("development", "http://localhost:53123") == "http://localhost:53123"
    assert preflight("development", "http://evil.example") is None
    assert preflight("test", "http://localhost:53123") is None
