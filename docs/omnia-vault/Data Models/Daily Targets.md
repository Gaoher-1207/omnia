---
type: data-model
status: planned
frontend: none
backend_available: true
backend_connected: false
---

# Daily Targets

Per-day numeric targets stored on the backend **profile**. They're what the backend and donor app call "daily goals". The canonical frontend doesn't have them yet.

| Target | Profile field | Default | Compared with (dashboard `today`) |
|---|---|---|---|
| Study | `daily_study_goal_minutes` | 240 min | `study_minutes` |
| Tasks | `daily_task_goal` | 5 | `tasks_completed` |
| Steps | `daily_step_goal` | 8000 | `steps` |
| Sleep | `daily_sleep_goal_minutes` | 480 min | `sleep_minutes` |
| Calories | `daily_calorie_goal` | 2000 kcal | `calories` |

Read: `GET /profile` or `GET /dashboard`. Write: `PATCH /profile`. See [[Profile and Dashboard API]].

They reset every day, measure consistency and feed streaks, the "balanced" day flag, achievements and the AI plan context.

> [!important]
> Daily targets are **not** long-term [[Goals]]. A long-term goal like *Read 12 books* accumulates over months and is completed by the user. A daily target like *8000 steps* restarts each day. See [[Goals vs Daily Targets]].

## In the code today

- Canonical: read-only since [[Phase 4 - Dashboard API Integration]]. In API mode Home and Track show the study, steps and sleep targets from `/dashboard` (`TodaySummary`); mock mode shows the sample 4 h, 8,000 steps, 8 h. There's no editor.
- Donor: `ApiGoalRepository` + `settings/goals_page.dart` present these five targets as "goals" ([[Fawaz Donor Map]]).

## Planned

A daily-targets editor in [[Settings]] (`PATCH /profile`), the next phase of the [[Backend Integration Roadmap]]. Real progress on [[Dashboard]] and [[Track]] arrived in [[Phase 4 - Dashboard API Integration]].
