# OMNIA API contract (frontend view)

What `Shehwaar/omnia_ui` sends and expects in **API mode**. A backend that satisfies this runs the frontend unchanged. The reference implementation is `Fawaz/backend` (FastAPI); its Swagger UI (`/api/docs`) documents far more than this page, because the frontend uses only part of it.

Source of truth for this page: the API repositories in `lib/` (`core/auth/auth_controller.dart`, `core/models/user.dart`, `features/*/data/api_*.dart`) and the fake backend the tests run against (`test/support/fake_auth_backend.dart`). If you change one, update this page.

**Field rules.** "Read" fields must be present with the listed type, or the screen shows a load error. Extra fields are ignored. `?` means the field may be `null`. Types are JSON types.

## Conventions

| | |
|---|---|
| Base URL | `OMNIA_API_BASE_URL`, including the `/api` prefix. Paths below are relative to it: `/tasks` → `https://host/api/tasks`. |
| Bodies | JSON, UTF-8. Requests send `Accept: application/json` and, with a body, `Content-Type: application/json; charset=utf-8`. |
| Auth | `Authorization: Bearer <access_token>` on every request once signed in. The token comes from login/register/change-password. |
| Ownership | The frontend **never sends a user id**. The backend must scope every resource to the token's user. |
| Days | `YYYY-MM-DD` calendar dates (no time zone). "Today" is decided by the **server**, in the profile's time zone, and read from `/dashboard`. |
| Times | Read as `HH:MM:SS` or `HH:MM`. The frontend sends a task's `due_time` as `HH:MM`, and sleep times exactly as it received them. |
| Timestamps | ISO 8601 (`created_at`). |
| Timeout | 20 s per request. |

### Errors

Any non-2xx response. The frontend reads this envelope when present, and falls back to a generic message otherwise:

```json
{
  "error": {
    "code": "validation_error",
    "message": "Shown to the user as is",
    "details": [ { "field": "body.steps", "message": "Must be 0 to 200000" } ]
  }
}
```

- `details[].field` is matched on its **last segment** (`body.steps` → the Steps field), so forms show the message under the right input.
- `401` **to a request that carried a token** clears the token and returns to sign-in. A `401` from login is just "wrong email or password".
- A network failure or timeout is shown as "Can't reach OMNIA…".

## Authentication

| Call | Request body | Success response |
|---|---|---|
| `POST /auth/register` | `display_name`, `email`, `password` (≥ 8), `timezone` (IANA) | `AuthResponse` |
| `POST /auth/login` | `email`, `password` | `AuthResponse` |
| `GET /auth/me` | — | `User` |
| `POST /auth/change-password` | `current_password`, `new_password` | `AuthResponse` (a new token; other devices signed out) |
| `POST /auth/logout-all` | — | ignored |
| `POST /auth/delete-account` | `password` | ignored |

Sign-out on this device is local (the token is forgotten); there is no logout call.

`AuthResponse`: `{ "access_token": string, "user": User }`

`User`: `{ "id": string, "email": string, "profile": Profile }`

`Profile`:

| Field | Type |
|---|---|
| `display_name` | string |
| `timezone` | string (IANA) |
| `username` | string? |
| `daily_study_goal_minutes`, `daily_step_goal`, `daily_task_goal`, `daily_sleep_goal_minutes`, `daily_calorie_goal` | int (0 = not tracking) |
| `preferred_workout_time` | `"morning"` \| `"afternoon"` \| `"evening"` |

## Profile and daily targets

| Call | Request body | Success response |
|---|---|---|
| `PATCH /profile` | only the changed `Profile` fields | `Profile` |

Limits the UI enforces before sending: study and sleep 0–960 min, steps 0–100000, tasks 0–50, calories 0–10000, username `^[a-z0-9_]{3,30}$`. Server-side refusals come back as field errors (e.g. a taken `username`).

## Dashboard (Today and Areas)

`GET /dashboard` → read fields:

| Field | Type | |
|---|---|---|
| `date` | day | the server's today in the user's time zone |
| `greeting` | `"morning"` \| `"afternoon"` \| `"evening"` | |
| `display_name` | string | |
| `today.study_minutes`, `today.study_goal_minutes` | int | |
| `today.steps`, `today.step_goal` | int | |
| `today.sleep_minutes` | int? | `null` = not logged (different from 0) |
| `today.sleep_goal_minutes` | int | |
| `next_exam` | object? | `null` = no upcoming exam |
| `next_exam.title`, `next_exam.subject_name` | string | |
| `next_exam.exam_date` | day | |
| `next_exam.days_left` | int | 0 = today |

It is reloaded after every activity, sleep or profile change and when the app returns to the foreground, so it must reflect writes immediately.

## Tasks

| Call | Request | Success response |
|---|---|---|
| `GET /tasks?limit=200&offset=N` | — | `{ "items": [Task], "total": int }` (paged until `offset ≥ total`) |
| `GET /tasks/{id}` | — | `Task` |
| `POST /tasks` | `TaskBody` | `Task` |
| `PATCH /tasks/{id}` | `TaskBody` + `status`, or only `{ "status": … }` | `Task` |
| `DELETE /tasks/{id}` | — | ignored |

`Task` (read): `id` string, `title` string, `notes` string?, `status` (`"done"` = completed, anything else = open), `priority` (`"low"` \| `"medium"` \| `"high"`; unknown → medium), `due_date` day?, `due_time` time?, `estimated_minutes` int?, `category` string (`study`, `tasks`, `activity`, `sleep`, `nutrition`, `habits`; unknown → `tasks`), `created_at` timestamp.

`TaskBody` (sent): `title`, `notes`, `priority`, `due_date`, `due_time` (`HH:MM`, `null` = all day), `estimated_minutes` (1–1440 or `null`), `category`. `status` is `"done"` or `"todo"`. On `PATCH`, an explicit `null` clears the field.

## Activity (one row per day)

| Call | Request | Success response |
|---|---|---|
| `GET /activity/{day}` | — | `Activity`; a day with nothing logged returns zeros, not 404 |
| `PUT /activity/{day}` | all four fields | `Activity` |
| `GET /activity?from=&to=` | days (≤ 93 apart) | `{ "step_goal": int, "days": [Activity + "id"] }`, every day in the range; a day never logged has `"id": null` and is **not** counted by Insights |

`Activity`: `day` day, `steps` int, `workout_done` bool, `workout_minutes` int, `workout_type` string?.

`PUT` **replaces the whole day**; the frontend always sends `steps` (0–200000), `workout_done`, `workout_minutes` (0–600) and `workout_type` (1–40 chars or `null`). With `workout_done: false` it sends `workout_minutes: 0` and `workout_type: null`. `workout_type` is free text: the app offers presets but preserves any stored value. A future `{day}` must be refused (`422` with a `details` entry).

## Sleep (the night ending on `{day}`)

| Call | Request | Success response |
|---|---|---|
| `GET /sleep/{day}` | — | `Sleep`; nothing logged → `{ "logged": false, … }` |
| `PUT /sleep/{day}` | all four fields | `Sleep` |
| `DELETE /sleep/{day}` | — | ignored |

`Sleep`: `logged` bool (`false` = not logged; the other fields are then ignored), `day` day, `duration_minutes` int (0–1440; 0 is a real, logged value), `quality` int? (1–5), `bedtime` time?, `wake_time` time?.

`PUT` replaces the entry. The app has no bedtime/wake-time inputs; it sends back whatever `GET` returned, so the backend must accept its own values. Future days must be refused.

## Study: subjects and exams

| Call | Request | Success response |
|---|---|---|
| `GET /study/subjects` | — | `[Subject]`, by name |
| `POST /study/subjects` | `{ "name": string }` (1–60, trimmed) | `Subject` (`201`) |
| `PATCH /study/subjects/{id}` | `{ "name": string }` | `Subject` |
| `DELETE /study/subjects/{id}` | — | ignored (`204`); **also deletes the subject's exams** |
| `GET /study/exams` | — | `[Exam]`, **upcoming only** (today or later in the user's time zone), nearest first |
| `POST /study/exams` | `ExamBody` | `Exam` (`201`) |
| `PATCH /study/exams/{id}` | `ExamBody` (all four fields) | `Exam` |
| `DELETE /study/exams/{id}` | — | ignored (`204`) |

`Subject` (read): `id` string, `name` string. `color` may be present and is ignored.

`Exam` (read): `id` string, `title` string, `exam_date` day, `notes` string?, `days_left` int (from the **server's** today; 0 = today), `subject` `{ "id": string, "name": string }`.

`ExamBody` (sent): `subject_id` (one of the user's subjects), `title` (1–120), `exam_date` day, `notes` (≤ 2000, or `null` to clear). Exams have no time or type.

Rules the frontend relies on:

- A duplicate subject name for the same user is refused with `409` (`error.message` is shown under the name field).
- Another user's subject or exam id answers `404`, like a missing one; deleting something already gone is treated as done.
- `GET /dashboard` `next_exam` is the first of `GET /study/exams`, so after any study change the app reloads the dashboard and Today follows.

Finished Focus phases are saved as study time with `POST /study/sessions` `{ "duration_minutes": int (1–720), "source": "focus", "started_at": timestamp }` (dated "today" by the server); the response is ignored and the dashboard reloads. `GET /study/sessions?from=&to=` lists study for Study's history and the Insights Study card; each session has `source` (`manual` \| `focus` \| `plan`).

## Long-term goals

| Call | Request | Success response |
|---|---|---|
| `GET /goals` | — | `[Goal]` |
| `POST /goals` | `GoalBody` | `Goal` (`201`, server-assigned `id`) |
| `PATCH /goals/{id}` | `GoalBody`, or `{ "completed": bool }` | `Goal` |
| `DELETE /goals/{id}` | — | ignored (`204`) |

`Goal`: `id`, `title`, `description`?, `category` (as tasks), `target_value` number?, `current_value` number?, `unit` string?, `deadline` day?, `completed` bool. Measurable goals have all three of target/current/unit; completion-only goals have none. `GoalBody` sends every field, so a cleared field is cleared on the server.

## Daily plan, outcomes and replanning

| Call | Request | Success response |
|---|---|---|
| `GET /ai/daily-plan?date=` | — | `Plan` (`404` = none yet) |
| `POST /ai/daily-plan` | `{ "regenerate": true }` | `Plan` |
| `POST /ai/daily-plan/{day}/items` | `{ "category", "start": "HH:MM", "duration_minutes", "title"? , "task_id"?, "subject_id"?, "base_revision"? }` | `Plan` with the block added (`manual: true`); 409 `plan_item_conflict` / `plan_stale`, 422 `plan_item_invalid` change nothing |
| `DELETE /ai/daily-plan/{day}/items/{item_key}?base_revision=` | — | `Plan` without the block (generated or manual); 409 `plan_item_stale` / `plan_stale` refresh the plan and remove nothing |
| `PUT /ai/daily-plan/{day}/items/{item_key}/outcome` | `{ "status": "done" \| "partial" \| "skipped", "minutes": int? }` (`minutes` only for a partly done study block) | `Plan` with that item's `outcome`; study blocks are credited as study time by the server |
| `DELETE /ai/daily-plan/{day}/items/{item_key}/outcome` | — | `Plan` with the outcome cleared |
| `POST /ai/replan/proposals` | `{ "request": string, "plan_date": day? }` | `Proposal` (`201`); the plan is unchanged |
| `GET /ai/replan/proposals/{id}` | — | `Proposal` |
| `POST /ai/replan/proposals/{id}/apply` | — | the new `Plan` revision |
| `POST /ai/replan/proposals/{id}/dismiss` | — | `Proposal` |
| `GET /commitments`, `POST`/`PUT`/`DELETE /commitments/{id}`, `GET /commitments/availability?day=` | | fixed commitments and free time |

Plan items carry `item_key` (stable across revisions) and `outcome` (`null` when nothing is recorded). `409` with `code: plan_item_stale` means the item is no longer in the latest plan: the app reloads the plan. `409` `replan_proposal_stale` / `replan_proposal_expired` and `422` `replan_invalid` retire the preview without changing anything.

## Ask Omnia (read-only assistant)

| Call | Body | Response |
|---|---|---|
| `POST /ai/chat` | `{ "message": string (1–1000), "history": [ { "role": "user" \| "assistant", "content": string (1–2000) } ] (≤ 10, oldest first) }` | `{ "reply": string, "source": string }` |

Rules the frontend relies on:

- The server builds the signed-in user's context itself; the body never carries ids, a user or context, and unknown fields are refused with `422`.
- Asking changes nothing on the server. When a question reads like a change to today's plan, the app offers a preview through `POST /ai/replan/proposals`; only the user's Apply changes the plan.
- `503` = the assistant is switched off, offline or has no model (shown as "unavailable", with `error.message`); `502` = the model timed out or gave an unusable answer; `429` = too many questions this hour.
- A first answer can take a while (the server may be loading its model), so the app waits up to 75 s.
- `reply` is plain text.

## Not used by the frontend (yet)

Present in the reference backend, not called: `/study/backlog`, `GET /study/sessions`, `/study/plan`, `/progress`, `/achievements`, `/meals` and nutrition, `/social/*`, `/integrations/*`.

Optional but recommended: `GET /health` → `{ "status": "ok" }`. The app doesn't call it; `run_frontend.ps1` and the checklist use it.
