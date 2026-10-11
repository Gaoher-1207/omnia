"""The suite runs on a frozen clock, and "today" is always the user's own day.

These guard the release foundation: results must not depend on the host's
timezone or on the wall-clock time a test run happens to start.
"""

import ast
import json
from datetime import UTC, datetime, timedelta
from pathlib import Path

from app.core import time as app_time
from tests.conftest import CLOCK_TARGETS, FROZEN_NOW, TODAY, auth_headers, register

APP = Path(__file__).resolve().parents[1] / "app"

# 12:00 UTC on 10 March is already 11 March in Kiritimati (UTC+14) and still
# 10 March in Pago Pago (UTC-11): the two users disagree with the host and each other.
AHEAD, BEHIND = "Pacific/Kiritimati", "Pacific/Pago_Pago"


def _modules_importing_utcnow() -> set[str]:
    found = set()
    for path in APP.rglob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.ImportFrom)
                and node.module == "app.core.time"
                and any(alias.name == "utcnow" for alias in node.names)
            ):
                module = ".".join(path.relative_to(APP.parent).with_suffix("").parts)
                found.add(f"{module}.utcnow")
    return found


def test_clock_covers_every_utcnow_import():
    assert _modules_importing_utcnow() <= set(CLOCK_TARGETS)


def test_server_clock_is_frozen_and_movable(clock):
    assert app_time.utcnow() == FROZEN_NOW
    assert TODAY == FROZEN_NOW.date() == app_time.local_today("UTC")
    later = datetime(2026, 3, 11, 23, 30, tzinfo=UTC)
    clock.set(later)
    assert app_time.utcnow() == later
    assert clock.today(AHEAD) == app_time.local_today(AHEAD)


def test_today_follows_each_users_timezone(client, clock):
    assert clock.today(AHEAD) == TODAY + timedelta(days=1)
    assert clock.today(BEHIND) == TODAY
    for tz in (AHEAD, BEHIND):
        headers = auth_headers(register(client, timezone=tz))
        today = clock.today(tz)
        assert client.get("/api/dashboard", headers=headers).json()["date"] == today.isoformat()
        # The user's own today is accepted; their tomorrow is rejected as a future day.
        assert client.put(f"/api/activity/{today}", json={"steps": 10}, headers=headers).status_code == 200
        tomorrow = today + timedelta(days=1)
        assert client.put(f"/api/activity/{tomorrow}", json={"steps": 10}, headers=headers).status_code == 422


def test_dates_roll_over_at_the_users_midnight(client, clock):
    headers = auth_headers(register(client, timezone=BEHIND))
    clock.set(datetime(2026, 3, 11, 10, 59, tzinfo=UTC))  # 23:59 on 10 March in Pago Pago
    assert client.get("/api/dashboard", headers=headers).json()["date"] == "2026-03-10"
    clock.set(datetime(2026, 3, 11, 11, 0, tzinfo=UTC))  # midnight there
    assert client.get("/api/dashboard", headers=headers).json()["date"] == "2026-03-11"


def test_export_is_stamped_with_the_users_local_date(client, clock):
    headers = auth_headers(register(client, timezone=AHEAD))
    data = json.loads(client.get("/api/account/export", headers=headers).content)
    assert data["exported_on"] == clock.today(AHEAD).isoformat() == "2026-03-11"
