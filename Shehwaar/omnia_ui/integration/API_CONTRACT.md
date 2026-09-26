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

## Not used by the frontend (yet)

Present in the reference backend, not called: `/study/*`, `/ai/daily-plan` (Phase 5C), `/progress`, `/achievements`, `/meals` and nutrition, `/social/*`, `/integrations/*`. Long-term Goals have **no endpoint anywhere**; the app keeps them in memory.

Optional but recommended: `GET /health` → `{ "status": "ok" }`. The app doesn't call it; `run_frontend.ps1` and the checklist use it.
