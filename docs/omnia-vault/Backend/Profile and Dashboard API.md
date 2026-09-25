---
type: backend
module: users, dashboard
backend_connected: partial
---

# Profile and Dashboard API

## Profile: `modules/users` · `/api/profile`

| Endpoint | Purpose |
|---|---|
| `GET /profile` | "Get my profile and daily goals" |
| `PATCH /profile` | "Update my profile and daily goals" |

`ProfileOut` / `ProfileUpdate` fields: `display_name`, `timezone` (IANA, validated), `username` (3–30 chars, `[a-z0-9_]`), `preferred_workout_time` (`morning` / `afternoon` / `evening`) and the five **[[Daily Targets]]**:

| Field | Default | Range |
|---|---|---|
| `daily_study_goal_minutes` | 240 | 0–960 |
| `daily_step_goal` | 8000 | 0–100000 |
| `daily_task_goal` | 5 | 0–50 |
| `daily_sleep_goal_minutes` | 480 | 0–960 |
| `daily_calorie_goal` | 2000 | 0–10000 |

> [!warning] Naming trap
> The backend calls these "daily goals" (`*_goal`). They are **not** the canonical long-term [[Goals]]. See [[Goals vs Daily Targets]].

## Dashboard: `modules/dashboard` · `/api/dashboard`

`GET /dashboard`, "Everything the Today screen needs in one call" (`DashboardOut`):

- `date`, `greeting` (`morning` / `afternoon` / `evening`), `display_name`
- `today`: study minutes vs goal, tasks completed vs goal, steps vs goal, workout status and minutes, sleep vs goal, calories vs goal
- `streaks` (from [[Progress API]])
- `next_exam` (with `days_left`), `upcoming_tasks` (`TaskOut[]`), `study_today` (plan blocks), `ai_plan` (stored plan, if any)

It aggregates across [[Tasks API]], [[Study API]], [[Activity API]], [[Sleep API]], [[Nutrition API]] and [[AI API]].

## Canonical usage

- `GET /dashboard`: used in API mode since [[Phase 4 - Dashboard API Integration]] (complete; manually verified on the Android emulator against the real backend). Read: `date`, `greeting`, `display_name`, `today.study_minutes`/`study_goal_minutes`, `today.steps`/`step_goal`, `today.sleep_minutes` (null = not logged)/`sleep_goal_minutes`, and `next_exam` (null = none). Not read yet: tasks, workout and calorie figures, `streaks`, `upcoming_tasks`, `study_today`, `ai_plan`.
- `PATCH /profile`: used in API mode since [[Phase 5A - Profile and Daily Targets]] (complete; manually verified on the Android emulator against the real backend). Settings → "Profile & daily targets" sends only the changed fields; the returned `ProfileOut` replaces the signed-in user's profile, then the dashboard reloads. A taken username (409 `conflict`, no field in `details`) is shown on the username field.
- `GET /profile`: not called; `/auth/me` already returns the full profile.

Related: [[API Map]] · [[User]]
