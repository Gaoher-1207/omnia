"""End-to-end check against a running OMNIA backend.

Replays the calls the Flutter app's repositories make, checks the JSON fields
the Dart parsers read, and (with --phase verify) confirms the data survived a
server restart.

    python scripts/integration_check.py --base http://127.0.0.1:8000/api --phase create
    # restart the backend
    python scripts/integration_check.py --base http://127.0.0.1:8000/api --phase verify

The throwaway account's email/password are kept in a local state file (default
./.integration_state.json, git-ignored) between the two phases.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import json
import secrets
import sys
from pathlib import Path
from zoneinfo import ZoneInfo

import httpx

ZONES = [
    "Pacific/Honolulu",
    "America/Los_Angeles",
    "America/Chicago",
    "America/New_York",
    "America/Sao_Paulo",
    "Atlantic/Azores",
    "Europe/London",
    "Europe/Berlin",
    "Europe/Moscow",
    "Asia/Dubai",
    "Asia/Kolkata",
    "Asia/Bangkok",
    "Asia/Shanghai",
    "Asia/Tokyo",
    "Australia/Sydney",
    "Pacific/Auckland",
]


def morning_zone() -> str:
    """A timezone where it's currently morning, so the day planner has hours left to fill."""
    now = dt.datetime.now(dt.UTC)
    return min(ZONES, key=lambda z: abs(now.astimezone(ZoneInfo(z)).hour + now.astimezone(ZoneInfo(z)).minute / 60 - 8))


CHECKS: list[str] = []
# PNG signature plus padding: passes the magic-byte check without being a real photo.
PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + bytes(64)).decode()


def ok(label: str) -> None:
    CHECKS.append(label)
    print(f"  ok  {label}")


def fail(label: str, detail: object) -> None:
    print(f"FAIL  {label}: {detail}")
    sys.exit(1)


def has_keys(label: str, obj: dict, keys: str) -> None:
    missing = [k for k in keys.split() if k not in obj]
    if missing:
        fail(label, f"missing keys {missing} in {sorted(obj)}")


def call(client: httpx.Client, method: str, path: str, expect: int = 200, **kw):
    r = client.request(method, path, **kw)
    if r.status_code != expect:
        fail(f"{method} {path}", f"HTTP {r.status_code}: {r.text[:300]}")
    return r.json() if r.content else None


def create(base: str, state_file: Path) -> None:
    email = f"it-{secrets.token_hex(4)}@example.com"
    password = secrets.token_urlsafe(12)
    zone = morning_zone()
    c = httpx.Client(base_url=base, timeout=30)

    call(c, "GET", "/health")
    ok("health")

    # AuthController.register → POST /auth/register, then stores access_token.
    reg = call(
        c,
        "POST",
        "/auth/register",
        201,
        json={"email": email, "password": password, "display_name": "Integration", "timezone": zone},
    )
    has_keys("register", reg, "access_token user")
    has_keys("user", reg["user"], "id email profile")
    has_keys(
        "profile",
        reg["user"]["profile"],
        "display_name timezone daily_step_goal daily_study_goal_minutes daily_task_goal "
        "daily_sleep_goal_minutes daily_calorie_goal username",
    )
    ok(f"register (timezone {zone})")

    call(c, "POST", "/auth/login", 401, json={"email": email, "password": "wrong-password"})
    login = call(c, "POST", "/auth/login", json={"email": email, "password": password})
    c.headers["Authorization"] = f"Bearer {login['access_token']}"
    ok("login (wrong password rejected, right one accepted)")

    me = call(c, "GET", "/auth/me")
    user_id = me["id"]
    call(c, "PATCH", "/profile", json={"username": "it_" + secrets.token_hex(3), "daily_step_goal": 9000})
    ok("profile update")

    # "Today" is the user's local day, exactly as the backend computes it.
    today = dt.datetime.now(ZoneInfo(zone)).date()
    exam_day = (today + dt.timedelta(days=10)).isoformat()
    today = today.isoformat()
    # Tasks (ApiTaskRepository)
    task = call(
        c,
        "POST",
        "/tasks",
        201,
        json={
            "title": "Lab report",
            "priority": "medium",
            "due_date": today,
            "due_time": "18:30",
            "estimated_minutes": 45,
            "category": "study",
        },
    )
    has_keys("task", task, "id title notes priority status due_date due_time estimated_minutes category created_at")
    done = call(c, "PATCH", f"/tasks/{task['id']}", json={"status": "done"})
    if done["status"] != "done" or not done["completed_at"]:
        fail("complete task", done)
    page = call(c, "GET", "/tasks", params={"limit": 100, "offset": 0})
    has_keys("task page", page, "items total")
    call(c, "POST", "/tasks", 201, json={"title": "Buy groceries", "priority": "low"})
    ok("task create + complete + list")

    # Study (ApiStudyRepository)
    subject = call(c, "POST", "/study/subjects", 201, json={"name": "DBMS"})
    has_keys("subject", subject, "id name color")
    call(c, "POST", "/study/subjects", 409, json={"name": "DBMS"})
    exam = call(
        c, "POST", "/study/exams", 201, json={"subject_id": subject["id"], "title": "Midterm", "exam_date": exam_day}
    )
    has_keys("exam", exam, "id title exam_date days_left subject")
    backlog = call(
        c,
        "POST",
        "/study/backlog",
        201,
        json={"subject_id": subject["id"], "title": "Normalization", "kind": "backlog", "estimated_minutes": 45},
    )
    has_keys("backlog", backlog, "id title kind status estimated_minutes subject")
    session = call(
        c,
        "POST",
        "/study/sessions",
        201,
        json={"subject_id": subject["id"], "session_date": today, "duration_minutes": 50},
    )
    has_keys("session", session, "id session_date duration_minutes subject")
    plan = call(c, "GET", "/study/plan", params={"days": 7})
    has_keys("study plan", plan, "days warnings")
    ok("study: subject (duplicate → 409), exam, backlog, session, plan")

    # Activity + sleep + meals (TrackRepository)
    act = call(c, "PUT", f"/activity/{today}", json={"steps": 6400, "workout_done": True, "workout_minutes": 30})
    has_keys("activity", act, "day steps workout_done workout_minutes workout_type")
    sleep = call(c, "PUT", f"/sleep/{today}", json={"duration_minutes": 330, "quality": 2})
    has_keys("sleep", sleep, "day duration_minutes quality")
    meal = call(
        c, "POST", "/meals", 201, json={"day": today, "meal_type": "lunch", "description": "Dal rice", "calories": 520}
    )
    has_keys("meal", meal, "id day meal_type description calories")
    call(c, "POST", "/nutrition/estimate", 503, json={"image_base64": PNG, "media_type": "image/png"})
    ok("activity, sleep, meal (photo estimate → 503 without an AI key)")

    # AI plan (PlanRepository) — adapts to the short night logged above.
    ai = call(c, "POST", "/ai/daily-plan", 201, json={"note": "slept badly", "regenerate": False})
    has_keys("ai plan", ai, "id plan_date source summary items adjustments tips is_fallback")
    if not ai["items"]:
        fail("ai plan", "no items")
    has_keys("plan item", ai["items"][0], "start end title category")
    if not any("slept" in a.lower() or "sleep" in a.lower() for a in ai["adjustments"]):
        fail("adaptive plan", ai["adjustments"])
    again = call(c, "POST", "/ai/daily-plan", 201, json={"note": "slept badly", "regenerate": True})
    ok(f"AI plan generated ({ai['source']}), adapts to poor sleep, regenerates")

    # Dashboard + progress (DashboardRepository / ProgressRepository)
    dash = call(c, "GET", "/dashboard")
    has_keys("dashboard", dash, "greeting date today upcoming_tasks next_exam ai_plan streaks")
    has_keys(
        "dashboard.today",
        dash["today"],
        "steps step_goal study_minutes study_goal_minutes tasks_completed task_goal workout_status "
        "workout_minutes sleep_minutes sleep_goal_minutes calories calorie_goal",
    )
    if dash["today"]["steps"] != 6400 or dash["today"]["tasks_completed"] != 1 or dash["today"]["study_minutes"] != 50:
        fail("dashboard numbers", dash["today"])
    progress = call(c, "GET", "/progress", params={"days": 7})
    has_keys("progress", progress, "streaks history")
    call(c, "GET", "/achievements")
    ok("dashboard + progress reflect the logged data")

    # Isolation: a second user cannot see or touch user 1's data.
    other = httpx.Client(base_url=base, timeout=30)
    tok = call(
        other,
        "POST",
        "/auth/register",
        201,
        json={
            "email": f"it-{secrets.token_hex(4)}@example.com",
            "password": secrets.token_urlsafe(12),
            "display_name": "Other",
            "timezone": "Asia/Calcutta",
        },
    )
    if tok["user"]["profile"]["timezone"] != "Asia/Kolkata":
        fail("timezone alias", tok["user"]["profile"]["timezone"])
    tok = tok["access_token"]
    other.headers["Authorization"] = f"Bearer {tok}"
    call(other, "GET", f"/tasks/{task['id']}", 404)
    call(other, "PATCH", f"/study/subjects/{subject['id']}", 404, json={"name": "hijack"})
    call(other, "POST", "/tasks", 422, json={"title": "mine", "user_id": user_id})
    call(other, "POST", "/tasks", 201, json={"title": "mine"})
    if call(c, "GET", "/tasks")["total"] != 2:
        fail("client user_id ignored", "task landed on user 1")
    call(httpx.Client(base_url=base), "GET", "/tasks", 401)
    ok("Asia/Calcutta → Asia/Kolkata; ownership: other user gets 404, client user_id rejected, no token → 401")

    state_file.write_text(
        json.dumps(
            {
                "email": email,
                "password": password,
                "task_id": task["id"],
                "subject_id": subject["id"],
                "plan_id": again["id"],
                "today": today,
            }
        )
    )
    print(f"\n{len(CHECKS)} checks passed. Restart the backend, then run --phase verify.")


def verify(base: str, state_file: Path) -> None:
    s = json.loads(state_file.read_text())
    c = httpx.Client(base_url=base, timeout=30)
    login = call(c, "POST", "/auth/login", json={"email": s["email"], "password": s["password"]})
    c.headers["Authorization"] = f"Bearer {login['access_token']}"
    ok("login after restart")

    task = call(c, "GET", f"/tasks/{s['task_id']}")
    if task["status"] != "done":
        fail("task persisted", task)
    subjects = call(c, "GET", "/study/subjects")
    if [x["id"] for x in subjects] != [s["subject_id"]]:
        fail("subject persisted", subjects)
    if not call(c, "GET", "/study/exams") or not call(c, "GET", "/study/backlog"):
        fail("exam/backlog persisted", "empty")
    sessions = call(c, "GET", "/study/sessions")
    if sum(x["duration_minutes"] for x in sessions) != 50:
        fail("session persisted", sessions)
    act = call(c, "GET", f"/activity/{s['today']}")
    if act["steps"] != 6400:
        fail("activity persisted", act)
    plan = call(c, "GET", "/ai/daily-plan")
    if plan["id"] != s["plan_id"]:
        fail("AI plan persisted", plan)
    dash = call(c, "GET", "/dashboard")
    if dash["today"]["tasks_completed"] != 1:
        fail("dashboard after restart", dash["today"])
    ok("task, subject, exam, backlog, session, activity, AI plan and dashboard all survived the restart")
    state_file.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8000/api")
    parser.add_argument("--phase", choices=["create", "verify"], required=True)
    parser.add_argument("--state", type=Path, default=Path(".integration_state.json"))
    args = parser.parse_args()
    (create if args.phase == "create" else verify)(args.base, args.state)
