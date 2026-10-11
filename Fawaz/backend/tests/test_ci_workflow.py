"""The repository's CI must gate releases: every check runs, and any failure fails the run.

GitHub only runs workflows from the repository root, so this reads that file.
"""

from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
WORKFLOWS = REPO / ".github" / "workflows"
CI = WORKFLOWS / "ci.yml"

# Skipped only outside a repository checkout (for example inside the backend container).
pytestmark = pytest.mark.skipif(not (REPO / ".git").exists(), reason="needs the full repository checkout")


def _text() -> str:
    return CI.read_text(encoding="utf-8")


def test_ci_is_the_only_workflow():
    assert sorted(path.name for path in WORKFLOWS.glob("*.y*ml")) == ["ci.yml"]


def test_ci_runs_every_backend_gate():
    text = _text()
    assert "working-directory: Fawaz/backend" in text
    for command in ("ruff check .", "ruff format --check .", "alembic check", "alembic downgrade base"):
        assert command in text, command
    # Tests on SQLite, then again on the PostgreSQL service.
    assert text.count("run: pytest") == 2
    assert "TEST_DATABASE_URL: ${{ env.PG_URL }}" in text
    assert "image: postgres:" in text
    # Migrations against both databases.
    assert text.count("alembic upgrade head") == 4
    assert "DATABASE_URL: ${{ env.SQLITE_URL }}" in text
    assert "DATABASE_URL: ${{ env.PG_URL }}" in text


def test_ci_runs_every_frontend_gate():
    text = _text()
    assert "working-directory: Shehwaar/omnia_ui" in text
    for command in ("flutter pub get", "flutter analyze", "flutter test", "flutter build web --release"):
        assert command in text, command


def test_ci_failures_are_not_swallowed():
    text = _text()
    for escape in ("|| true", "continue-on-error", "set +e", "Fawz/", "manage.py"):
        assert escape not in text, escape
