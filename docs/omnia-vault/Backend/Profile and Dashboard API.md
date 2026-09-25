---
type: backend
module: users, dashboard
backend_connected: false
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

None yet. It's planned for the dashboard phase. See [[Dashboard]] and [[Backend Integration Roadmap]].

Related: [[API Map]] · [[User]]
