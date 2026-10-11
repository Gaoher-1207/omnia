import os

os.environ.update(
    {
        "APP_ENV": "test",
        "DATABASE_URL": "sqlite://",
        "AUTH_SECRET": "test-secret-that-is-long-enough-for-hs256-signing",
        "PASSWORD_HASH_N": "1024",
        "AI_PROVIDER": "rules",
        "PLANNER_AI_PROVIDER": "rules",
        "OMNIA_AI_PROVIDER": "off",
        # Never reach a real model from tests, whatever a developer's .env says.
        "ASSISTANT_PROVIDER": "off",
        "AUTH_RATE_LIMIT_PER_MINUTE": "1000",
        "AI_RATE_LIMIT_PER_HOUR": "1000",
    }
)

import itertools  # noqa: E402
from datetime import UTC, date, datetime  # noqa: E402
from zoneinfo import ZoneInfo  # noqa: E402

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine, event  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import get_settings  # noqa: E402
from app.core.rate_limit import limiter  # noqa: E402
from app.db.session import get_db  # noqa: E402
from app.main import create_app  # noqa: E402
from app.models import Base  # noqa: E402

_counter = itertools.count(1)

# Every test runs at one fixed instant unless it moves the clock itself. Midday UTC
# keeps the date the same for test users in any timezone from UTC-11 to UTC+11, and
# the result never depends on the host's timezone or the wall-clock time of the run.
FROZEN_NOW = datetime(2026, 3, 10, 12, 0, tzinfo=UTC)
# "Today" for a default test user, whose profile timezone is UTC (see `register`).
TODAY = FROZEN_NOW.date()

# Modules that bind `utcnow` by name. `local_now`/`local_today` read
# `app.core.time.utcnow`, so patching these covers every server-side clock read.
# test_clock_covers_every_utcnow_import keeps this list complete.
CLOCK_TARGETS = (
    "app.core.time.utcnow",
    "app.modules.ai.assistant.utcnow",
    "app.modules.ai.service.utcnow",
    "app.modules.study.service.utcnow",
    "app.modules.tasks.service.utcnow",
)


class Clock:
    """The server's frozen 'now'. Tests move it with `clock.set(moment)`."""

    def __init__(self, now: datetime):
        self.now = now

    def set(self, moment: datetime) -> None:
        if moment.tzinfo is None:
            raise ValueError("clock.set needs an aware datetime")
        self.now = moment

    def today(self, tz: str = "UTC") -> date:
        """The calendar day a user in `tz` sees at the frozen instant."""
        return self.now.astimezone(ZoneInfo(tz)).date()


@pytest.fixture(autouse=True)
def clock(monkeypatch):
    frozen = Clock(FROZEN_NOW)
    for target in CLOCK_TARGETS:
        monkeypatch.setattr(target, lambda: frozen.now)
    return frozen


@pytest.fixture
def engine():
    """In-memory SQLite by default; set TEST_DATABASE_URL to run the suite against PostgreSQL."""
    url = os.environ.get("TEST_DATABASE_URL")
    if url:
        engine = create_engine(url)
        Base.metadata.drop_all(engine)
    else:
        engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)

        @event.listens_for(engine, "connect")
        def _fk(dbapi_connection, _record):
            dbapi_connection.execute("PRAGMA foreign_keys=ON")

    Base.metadata.create_all(engine)
    yield engine
    if url:
        Base.metadata.drop_all(engine)
    engine.dispose()


@pytest.fixture
def db(engine):
    session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()
    yield session
    session.close()


@pytest.fixture
def app(engine):
    factory = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    def _get_db():
        session = factory()
        try:
            yield session
        finally:
            session.close()

    application = create_app()
    application.dependency_overrides[get_db] = _get_db
    limiter.reset()
    get_settings.cache_clear()
    yield application
    limiter.reset()


@pytest.fixture
def client(app):
    with TestClient(app) as c:
        yield c


def register(client, **overrides):
    n = next(_counter)
    body = {
        "email": f"user{n}@example.com",
        "password": "correct-horse-battery",
        "display_name": f"Tester {n}",
        "timezone": "UTC",
    }
    body.update(overrides)
    response = client.post("/api/auth/register", json=body)
    assert response.status_code == 201, response.text
    return response.json()


def auth_headers(token_payload):
    return {"Authorization": f"Bearer {token_payload['access_token']}"}


@pytest.fixture
def user(client):
    return register(client)


@pytest.fixture
def headers(user):
    return auth_headers(user)


@pytest.fixture
def other_headers(client):
    return auth_headers(register(client))
