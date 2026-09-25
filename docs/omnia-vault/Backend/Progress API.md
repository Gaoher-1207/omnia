---
type: backend
module: progress
backend_connected: false
---

# Progress API

`modules/progress`. No table of its own: it computes everything from tasks, study sessions, activity, sleep and meals.

| Endpoint | Returns |
|---|---|
| `GET /progress?days=1..90` (default 14) | `streaks` + `history[]` |
| `GET /achievements` | 12 achievements, each with progress |

**Streaks** (`study`, `tasks`, `fitness`, `balance`): `current`, `longest`, `active_today`.
**History day:** `study_minutes`, `tasks_completed`, `steps`, `workout_done`, `balanced`, `sleep_minutes`, `calories`.
**Achievements:** fixed definitions in `achievements.py`, e.g. `first_study`, `study_streak_7`, `tasks_100`, `workouts_10`, `sleep_7`.

Frontend: [[Insights]] (sample). The concept of a broader, cross-module milestone record is in [[Achievements and Life Timeline]].

Related: [[API Map]] · [[Profile and Dashboard API]] (the dashboard embeds streaks)
