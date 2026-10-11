"""Migrations are a release step, never part of the API container's start."""

from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
COMPOSE = BACKEND.parent / "docker-compose.yml"


def test_api_container_does_not_migrate_on_start():
    cmd = next(line for line in (BACKEND / "Dockerfile").read_text().splitlines() if line.startswith("CMD"))
    assert "alembic" not in cmd
    assert "uvicorn" in cmd


def test_compose_runs_migrations_once_before_the_api():
    if not COMPOSE.exists():  # inside the backend image
        return
    text = COMPOSE.read_text()
    assert 'command: ["alembic", "upgrade", "head"]' in text
    assert "condition: service_completed_successfully" in text
