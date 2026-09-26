---
type: backend
module: sleep
backend_connected: false
---

# Sleep API

`modules/sleep` · prefix `/api/sleep`. Table `sleep_logs` (added in migration `0002`).

| Endpoint | Purpose |
|---|---|
| `GET /sleep?from=&to=` | Range, default last 14 days, max 93 |
| `GET /sleep/{day}` | The night **ending** on that day |
| `PUT /sleep/{day}` | Create or replace |
| `DELETE /sleep/{day}` | Remove |

Fields: `duration_minutes`, `quality` (optional), `bedtime`, `wake_time`.

Canonical frontend: `ApiTrackRepository` since [[Phase 5B - Activity and Sleep Logging]] (GET, whole-row PUT that sends `bedtime`/`wake_time` back unchanged, DELETE). Consumers: the dashboard (vs `daily_sleep_goal_minutes`), the "Well rested" achievement and the **AI plan context** (`last_night_sleep`). The rules planner treats short or poor sleep, or a "tired" note, as a signal to lighten the day. See [[AI API]].

Frontend: [[Sleep and Recovery]] (sample only).

Related: [[API Map]]
