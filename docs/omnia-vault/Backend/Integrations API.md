---
type: backend
module: integrations
backend_connected: false
---

# Integrations API

`modules/integrations` (migration `0004`).

## Calendar feed

| Endpoint | Purpose |
|---|---|
| `POST /integrations/calendar` | Create or replace my private subscription link. Only a hash of the token is stored. |
| `DELETE /integrations/calendar` | Revoke it |
| `GET /integrations/calendar/{token}.ics` | The iCalendar feed. **No login**, because the secret link is the credential. |

The feed contains exams (from 30 days ago onward, all-day), **open tasks with a due date** (timed when `due_time` is set, with an end of due time + estimate or 60 min, otherwise all-day), and today's AI plan. It needs `PUBLIC_BASE_URL` to build links.

## Data export

`GET /account/export` downloads all of the user's data as JSON.

## Canonical usage

None. Both would fit in [[Settings]] later. Once [[Phase 3 - Tasks API Integration]] is done, tasks created in the app would start appearing in a subscribed calendar with no further work.

Related: [[API Map]] · [[Tasks API]]
