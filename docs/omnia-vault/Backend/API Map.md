---
type: backend
---

# API Map

Every route registered in `Fawaz/backend/app/main.py`, all under the `/api` prefix. It was extracted from the router decorators, not from the README. **Used by canonical** = called by `Shehwaar/omnia_ui` today.

## Health

| Method | Path | Purpose | Used by canonical |
|---|---|---|---|
| GET | `/health` | Liveness | — |
| GET | `/health/ready` | DB readiness | — |

## Auth · [[Authentication API]]

| Method | Path | Used by canonical |
|---|---|---|
| POST | `/auth/register` | ✅ |
| POST | `/auth/login` | ✅ |
| GET | `/auth/me` | ✅ |
| POST | `/auth/delete-account` | ✅ |
| POST | `/auth/change-password` | ✅ |
| POST | `/auth/logout-all` | ✅ |

## Profile & dashboard · [[Profile and Dashboard API]]

| Method | Path | Used by canonical |
|---|---|---|
| GET | `/profile` | — |
| PATCH | `/profile` | — |
| GET | `/dashboard` | ✅ `ApiDashboardRepository.getDashboard` (date, greeting, display name, today's study/steps/sleep and targets, next exam) |

## Tasks · [[Tasks API]]

| Method | Path | Used by canonical |
|---|---|---|
| GET | `/tasks` (`status`, `priority`, `due_on_or_before`, `limit` ≤200, `offset`) | ✅ `ApiTaskRepository.getTasks` (pages of 200) |
| POST | `/tasks` | ✅ `createTask` |
| GET | `/tasks/{task_id}` | ✅ `getTask` |
| PATCH | `/tasks/{task_id}` | ✅ `updateTask`, `setCompleted` |
| DELETE | `/tasks/{task_id}` | ✅ `deleteTask` |

## Study · [[Study API]]

| Method | Path |
|---|---|
| GET · POST | `/study/subjects` |
| PATCH · DELETE | `/study/subjects/{subject_id}` |
| GET (`include_past`) · POST | `/study/exams` |
| PATCH · DELETE | `/study/exams/{exam_id}` |
| GET (`status`, `subject_id`) · POST | `/study/backlog` |
| PATCH · DELETE | `/study/backlog/{item_id}` |
| GET (`from`, `to`) · POST | `/study/sessions` |
| DELETE | `/study/sessions/{session_id}` |
| GET (`days` 1–28) | `/study/plan` |

## Activity · Sleep · Nutrition

| Method | Path | Note |
|---|---|---|
| GET | `/activity` (`from`, `to`) | [[Activity API]] |
| GET · PUT | `/activity/{day}` | upsert |
| GET | `/sleep` (`from`, `to`) | [[Sleep API]] |
| GET · PUT · DELETE | `/sleep/{day}` | upsert |
| GET (`day`) · POST | `/meals` | [[Nutrition API]] |
| PATCH · DELETE | `/meals/{meal_id}` | |
| GET | `/nutrition/summary` (`from`, `to`) | |
| POST | `/nutrition/estimate` | photo; 503 without an AI provider |

## Progress · [[Progress API]]

| Method | Path |
|---|---|
| GET | `/progress` (`days` 1–90) |
| GET | `/achievements` |

## Social · [[Social API]]

| Method | Path |
|---|---|
| GET | `/social/users/{username}` |
| GET | `/social/friends` |
| POST | `/social/friends/requests` |
| POST | `/social/friends/requests/{request_id}/accept` · `/decline` |
| DELETE | `/social/friends/{user_id}` |
| GET · POST | `/social/groups` |
| GET · PATCH · DELETE | `/social/groups/{group_id}` |
| POST | `/social/groups/{group_id}/members` |
| DELETE | `/social/groups/{group_id}/members/{user_id}` |
| GET (`after`, `limit`) · POST | `/social/groups/{group_id}/messages` |
| GET | `/social/feed` |
| POST | `/social/posts` |
| DELETE | `/social/posts/{post_id}` |
| POST · DELETE | `/social/posts/{post_id}/like` |
| GET · POST | `/social/groups/{group_id}/challenges` |
| GET | `/social/challenges/{challenge_id}` |
| POST · DELETE | `/social/challenges/{challenge_id}/join` |

## Integrations · [[Integrations API]]

| Method | Path |
|---|---|
| POST · DELETE | `/integrations/calendar` |
| GET | `/integrations/calendar/{token}.ics` (secret link, no login) |
| GET | `/account/export` |

## AI · [[AI API]]

| Method | Path |
|---|---|
| POST | `/ai/daily-plan` (`regenerate`, `note`) |
| GET | `/ai/daily-plan` (`date`) |

**Totals:** 6 of the backend's routes are used by the canonical frontend, all of them `/auth/*`.

Related: [[Backend Overview]] · [[Frontend Backend Integration]]
