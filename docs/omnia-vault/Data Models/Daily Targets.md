---
type: data-model
status: api-connected
frontend: canonical
backend_available: true
backend_connected: true
---

# Daily Targets

Per-day numeric targets stored on the backend **profile**. They're what the backend and donor app call "daily goals". In the canonical app they are `Profile` fields, edited in Settings since [[Phase 5A - Profile and Daily Targets]].

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

- Canonical: shown on Home and Track since [[Phase 4 - Dashboard API Integration]] (study, steps and sleep, from `/dashboard`); edited in Settings → "Profile & daily targets" since [[Phase 5A - Profile and Daily Targets]] (all five, 0 = not tracking), API mode only. Mock mode shows the sample 4 h, 8,000 steps, 8 h and has no editor.
- Donor: `ApiGoalRepository` + `settings/goals_page.dart` present these five targets as "goals" ([[Fawaz Donor Map]]).

## Planned

Delivered: the editor ([[Phase 5A - Profile and Daily Targets]]) and real progress on [[Dashboard]] and [[Track]] ([[Phase 4 - Dashboard API Integration]]). The task and calorie targets are editable but not displayed yet (the Home Tasks card keeps its all-tasks meaning; there's no nutrition UI).
