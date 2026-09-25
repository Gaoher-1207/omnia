---
type: backend
module: activity
backend_connected: false
---

# Activity API

`modules/activity` · prefix `/api/activity`. Table `activity_days`, one row per user per day.

| Endpoint | Purpose |
|---|---|
| `GET /activity?from=&to=` | Range (default: the 14 days ending today, in the user's time zone) |
| `GET /activity/{day}` | One day |
| `PUT /activity/{day}` | Create or replace the day |

Fields: `steps`, `workout_done`, `workout_minutes`, `workout_type` (≤40 chars).

It's a **daily summary**, not a workout log: no exercises, sets or weights. Feeds the dashboard (`steps` vs `daily_step_goal`), the `fitness` and `balance` streaks, and the achievements "On the move" and "Ten workouts".

Frontend: [[Fitness and Activity]], shown on [[Track]]. Future design: [[Fitness Roadmap]].

Related: [[API Map]]
