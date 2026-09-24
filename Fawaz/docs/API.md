# OMNIA API contract

Covers Phases 1–4. Status: **for team review** (Fawz ↔ Shew for integration, Rahaman/Ausaaf for security). How the Flutter app uses these endpoints: [INTEGRATION.md](INTEGRATION.md).
The live, always-current reference is the OpenAPI page at `http://localhost:8000/api/docs` when the backend runs in development.

## Conventions

| Topic | Rule |
|---|---|
| Base path | Everything is under `/api`. |
| Format | JSON in and out. Dates are `YYYY-MM-DD`; timestamps are ISO 8601 in UTC; ids are UUIDs. |
| Auth | `Authorization: Bearer <access_token>` on every route except `/health*`, `/auth/register` and `/auth/login`. |
| Ownership | The user comes **only** from the token. Bodies can't carry `user_id` (unknown fields are rejected). Another user's resource answers **404**, never 403, so ids can't be probed. |
| "Today" | Always today in the user's profile timezone, not the server's. |
| Success shape | The resource itself (no envelope). Paginated lists: `{ "items": [...], "total", "limit", "offset" }`. |
| Error shape | Always `{ "error": { "code", "message", "details"?, "request_id"? } }`. `details` is a list of `{ "field", "message" }` for validation errors. Submitted values are never echoed back. |
| Status codes | 200 OK · 201 created · 204 deleted · 400 bad query · 401 not signed in / expired / revoked · 403 wrong password on a protected action · 404 not found or not yours · 409 duplicate · 413 body too large (`MAX_REQUEST_BYTES`) · 422 validation · 429 rate limited (`Retry-After` header) · 500 generic · 502 AI provider failed (photo estimate) · 503 feature not configured. |
| Request id | Send `X-Request-ID` or get one back; it appears in error bodies and server logs. |

Error codes: `unauthorized`, `forbidden`, `not_found`, `conflict`, `validation_error`, `rate_limited`, `bad_request`, `payload_too_large`, `internal_error`, and for the photo estimate `service_unavailable` (503) / `upstream_error` (502).

## Privacy classification

| Class | Data | Rule |
|---|---|---|
| Credentials | password hash, tokens | Never returned, never logged. |
| Private | profile, goals, tasks, notes, study, activity, sleep, meals, AI plans | Owner only. |
| Shared by choice | display name + username (`PublicUser`); numbers the user picks for a post; challenge totals after joining; group messages | Friends / group members only. Nothing is shared automatically. |
| Secret link | calendar feed | Anyone with the link; stored hashed, revocable. |
| Sent to an AI provider | goals, today/yesterday totals, last night's sleep, streak counts, exam subject/title/days left, study block titles, open task titles (≤80 chars, as `t1…` refs), the user's optional note, account age in days; for photo estimates only the photo and optional note | Only when `AI_PROVIDER=anthropic`. No email, name, ids, task notes or timezone. |

---

## Health

| Method & path | Auth | Response |
|---|---|---|
| `GET /health` | none | `{"status":"ok"}`: process is up |
| `GET /health/ready` | none | `{"status":"ok","database":"ok"}`: database answers |

## Auth

| Method & path | Body | Success | Errors |
|---|---|---|---|
| `POST /auth/register` | `email`, `password` (8–128), `display_name` (1–60), `timezone` (IANA, default `UTC`; legacy names like `Asia/Calcutta` are stored as `Asia/Kolkata`) | 201 `TokenOut` | 409 email exists · 422 · 429 (per IP) |
| `POST /auth/login` | `email`, `password` | 200 `TokenOut` | 401 "Incorrect email or password" (same message and timing for unknown email) · 429 (per IP + email) |
| `GET /auth/me` | | 200 `User` | 401 |
| `POST /auth/delete-account` | `password` | 204, and all the user's data is deleted | 403 wrong password · 429 |
| `POST /auth/change-password` | `current_password`, `new_password` (8–128) | 200 `TokenOut` (new token; every older token stops working) | 403 wrong password · 429 |
| `POST /auth/logout-all` | | 204; every token issued so far stops working, including this one | 401 |

`TokenOut`: `{ access_token, token_type: "bearer", expires_in (seconds), user }`
`User`: `{ id, email, created_at, profile }`

```json
POST /api/auth/login
{ "email": "demo@omnia.app", "password": "omnia-demo-123" }

200
{ "access_token": "eyJ...", "token_type": "bearer", "expires_in": 43200,
  "user": { "id": "…", "email": "demo@omnia.app", "created_at": "…",
            "profile": { "display_name": "Sam", "timezone": "Asia/Kolkata",
                         "daily_study_goal_minutes": 240, "daily_step_goal": 8000,
                         "daily_task_goal": 5, "preferred_workout_time": "evening",
                         "daily_sleep_goal_minutes": 480, "daily_calorie_goal": 2000, "username": "sam_demo" } } }
```

## Profile

| Method & path | Body | Success | Errors |
|---|---|---|---|
| `GET /profile` | | `Profile` | 401 |
| `PATCH /profile` | any of: `display_name` (1–60), `timezone`, `daily_study_goal_minutes` (0–960), `daily_step_goal` (0–100000), `daily_task_goal` (0–50), `preferred_workout_time` (`morning`/`afternoon`/`evening`), `daily_sleep_goal_minutes` (0–960), `daily_calorie_goal` (0–10000), `username` (3–30 of `a-z 0-9 _`, lower-cased, unique) | `Profile` | 409 username taken · 422 (including explicit `null`) |

## Dashboard

`GET /dashboard` returns everything the Today screen needs in one call:

```json
{ "date": "2026-09-24", "greeting": "morning", "display_name": "Sam",
  "today": { "study_minutes": 90, "study_goal_minutes": 240, "tasks_completed": 1, "task_goal": 5,
             "steps": 3200, "step_goal": 8000, "workout_status": "pending", "workout_minutes": 0,
             "sleep_minutes": 385, "sleep_goal_minutes": 480, "calories": 940, "calorie_goal": 2000 },
  "streaks": { "study": {"current": 8, "longest": 8, "active_today": true}, "tasks": {…}, "fitness": {…}, "balance": {…} },
  "next_exam": { "id": "…", "title": "Physics semester exam", "subject_name": "Physics", "exam_date": "2026-10-02", "days_left": 8 },
  "upcoming_tasks": [Task, … up to 5],
  "study_today": [PlanBlock, …],
  "ai_plan": AIPlan | null }
```

Empty state: zeros, `next_exam: null`, empty lists, `ai_plan: null`.

## Tasks

| Method & path | Input | Success | Errors |
|---|---|---|---|
| `GET /tasks` | query: `status` (`todo`/`done`), `priority`, `due_on_or_before` (date), `limit` (1–200, default 50), `offset` | `Page<Task>`: open first, then by due date (no date last), then priority | 422 |
| `POST /tasks` | `title` (1–200, trimmed), `notes` (≤2000), `priority` (default `medium`), `due_date`, `due_time` (`HH:MM`, needs `due_date`), `estimated_minutes` (1–1440), `category` (`study`/`tasks`/`activity`/`sleep`/`nutrition`/`habits`, default `tasks`) | 201 `Task` | 422 |
| `GET /tasks/{id}` | | `Task` | 404 |
| `PATCH /tasks/{id}` | any create field, plus `status`. `status: "done"` sets `completed_at`; `"todo"` clears it. Clearing `due_date` clears `due_time` | `Task` | 404 · 422 |
| `DELETE /tasks/{id}` | | 204 | 404 |

`Task`: `{ id, title, notes, priority, status, due_date, due_time, estimated_minutes, category, completed_at, created_at, updated_at }`

## Study

| Method & path | Input | Success | Errors |
|---|---|---|---|
| `GET /study/subjects` | | `Subject[]` by name | |
| `POST /study/subjects` | `name` (1–60, unique per user), `color` (`#RRGGBB`) | 201 | 409 duplicate · 422 |
| `PATCH /study/subjects/{id}` | `name`, `color` | 200 | 404 · 409 · 422 |
| `DELETE /study/subjects/{id}` | | 204; deletes its exams and backlog, keeps sessions with `subject: null` | 404 |
| `GET /study/exams` | query `include_past` (default false) | `Exam[]` by date, each with `days_left` | |
| `POST /study/exams` | `subject_id` (must be yours), `title` (1–120), `exam_date`, `notes` | 201 `Exam` | 404 subject · 422 |
| `PATCH` / `DELETE /study/exams/{id}` | | 200 / 204 | 404 |
| `GET /study/backlog` | query `status` (`pending`/`done`), `subject_id` | `BacklogItem[]` | |
| `POST /study/backlog` | `subject_id`, `title` (1–200), `kind` (`backlog`/`revision`), `estimated_minutes` (5–600) | 201 | 404 · 422 |
| `PATCH /study/backlog/{id}` | any field, including `status` (sets/clears `completed_at`) | 200 | 404 · 422 |
| `DELETE /study/backlog/{id}` | | 204 | 404 |
| `GET /study/sessions` | query `from`, `to` (default: last 14 days, max 1 year) | `StudySession[]` newest first | 400 bad range |
| `POST /study/sessions` | `duration_minutes` (1–720), optional `subject_id`, `backlog_item_id`, `session_date` (default today, not in the future), `notes`, `complete_backlog_item` | 201 | 404 · 422 future date or subject ≠ item's subject |
| `DELETE /study/sessions/{id}` | | 204 | 404 |
| `GET /study/plan` | query `days` (1–28, default 7) | `StudyPlan` | 422 |

`StudyPlan`: `{ start_date, days: [{ date, available_minutes, planned_minutes, blocks: [PlanBlock], exams: [{exam_id, subject_name, title}] }], unscheduled_minutes, warnings: [string] }`
`PlanBlock`: `{ subject_id, subject_name, backlog_item_id | null, title, minutes, reason }`

Planner rules are documented at the top of `backend/app/modules/study/planner.py`.

## Activity

| Method & path | Input | Success | Errors |
|---|---|---|---|
| `GET /activity` | query `from`, `to` (default last 14 days, max 93) | `{ start, end, step_goal, days: [ActivityDay] }`, every day present (zeros if not logged) | 422 |
| `GET /activity/{day}` | | `ActivityDay` (zeros if not logged) | 422 bad date |
| `PUT /activity/{day}` | `steps` (0–200000), `workout_done`, `workout_minutes` (0–600), `workout_type` (≤40) | 200 `ActivityDay`. Idempotent: a repeat submit updates the same row | 422 future date |

## Progress

`GET /progress?days=14` (1–90) → `{ date, streaks, history: [{ date, study_minutes, tasks_completed, steps, workout_done, balanced, sleep_minutes, calories }] }`

`GET /achievements` → `[{ code, title, description, earned, progress, target }]`, computed from the user's own data (first study session, streak milestones and similar).

Streak rules (in `backend/app/modules/progress/streaks.py`): a day counts for **study** with ≥1 session, **tasks** with ≥1 completed task, **fitness** with a workout or the step goal, **balance** with at least two of those three. A streak still counts if today isn't active yet.

## AI daily plan

| Method & path | Input | Success | Errors |
|---|---|---|---|
| `POST /ai/daily-plan` | `regenerate` (default false), `note` (≤280, e.g. "slept badly") | **200** with today's existing plan, or **201** with a new one | 422 · 429 (per user per hour, new generations only) |
| `GET /ai/daily-plan` | query `date` (default today) | latest `AIPlan` for that date | 404 none yet |

`AIPlan`: `{ id, plan_date, source ("rules" | "anthropic"), is_fallback, created_at, summary, items: [{ start "HH:MM", end, category (study/task/fitness/break/recovery/other), title, detail, task_id | null, subject_id | null }], tips: [string], adjustments: [string] }`

Adaptation: after a night under 6 h or rated ≤ 2, study is split into shorter blocks and the reason is added to `adjustments`. Late in the user's day the plan may have no items ("The day is nearly over…").

Reliability rules:
- Provider output is validated (time format, order, no overlaps, lengths). Invalid output, timeouts (`AI_TIMEOUT_SECONDS`), 429s and 5xx all fall back to the rule-based planner, so the call still returns a plan with `is_fallback: true`. The reason is stored server-side, not returned.
- `task_id` is only set when the provider used one of the refs it was given.
- The frontend never talks to the provider; the key stays on the server.

## Sleep (Phase 2)

| Method & path | Input | Success | Errors |
|---|---|---|---|
| `GET /sleep` | query `from`, `to` (default last 14 days) | `{ start, end, goal_minutes, average_minutes, days: [Sleep] }`, every day present (`logged: false` if not logged) | 422 |
| `GET /sleep/{day}` | | `Sleep` | 422 |
| `PUT /sleep/{day}` | `duration_minutes` (0–1440), `quality` (1–5), `bedtime`, `wake_time` (`HH:MM`) | 200 `Sleep`; idempotent | 422 future date |
| `DELETE /sleep/{day}` | | 204 | 404 |

`Sleep`: `{ id, day, duration_minutes, quality, bedtime, wake_time, logged }`. `day` is the date you woke up.

## Meals and nutrition (Phase 2)

| Method & path | Input | Success | Errors |
|---|---|---|---|
| `GET /meals` | query `day` (default today) | `{ day, calorie_goal, totals, meals: [Meal] }` | 422 |
| `POST /meals` | `meal_type` (`breakfast`/`lunch`/`dinner`/`snack`), `description` (1–200), `calories` (0–5000), `protein_g`, `carbs_g`, `fat_g`, `day` (default today, not future), `source` (`manual`/`photo_estimate`) | 201 `Meal` | 422 |
| `PATCH /meals/{id}` | any of the above except `day`/`source` | `Meal` | 404 · 422 |
| `DELETE /meals/{id}` | | 204 | 404 |
| `GET /nutrition/summary` | query `from`, `to` | `{ start, end, calorie_goal, days: [{ day, calories, protein_g, carbs_g, fat_g }] }` | 422 |
| `POST /nutrition/estimate` | `image_base64` (≤ 5 MB decoded; JPEG/PNG/WebP, checked by magic bytes), `media_type`, `note` (≤200) | `{ items: [{ name, portion, calories, protein_g, carbs_g, fat_g }], totals, confidence, suggested_description, disclaimer }`. **Nothing is saved**: the app shows it for editing, then calls `POST /meals` with `source: "photo_estimate"` | 422 not an image · 429 · 502 provider failed · 503 no AI provider configured |

## Social (Phase 3)

Only `PublicUser` (`{ id, display_name, username }`) is ever shown to other people. Numbers are read on the server, so a client cannot post made-up progress.

| Method & path | Input | Success | Errors |
|---|---|---|---|
| `GET /social/users/{username}` | exact username | `PublicUser` | 404 · 429 |
| `GET /social/friends` | | `{ friends: [PublicUser], incoming: [Request], outgoing: [Request] }` | |
| `POST /social/friends/requests` | `username` | 201 `Friends` (accepts automatically if they already asked you) | 404 · 409 already friends/pending · 422 yourself · 429 (30/h) |
| `POST /social/friends/requests/{id}/accept` · `/decline` | | `Friends` | 404 (only the recipient can answer) |
| `DELETE /social/friends/{user_id}` | | 204: unfriend or cancel a request | 404 |
| `GET /social/groups` · `POST /social/groups` | `name` (1–60), `description` (≤300) | `Group[]` · 201 `Group` (you are the owner) | 422 |
| `GET /social/groups/{id}` | | `GroupDetail` with `members` | 404 if not a member |
| `PATCH` / `DELETE /social/groups/{id}` | `name`, `description` | `Group` / 204 | 403 not owner · 404 |
| `POST /social/groups/{id}/members` | `user_id` of one of **your friends** | `GroupDetail` | 403 not owner or not your friend · 409 already in |
| `DELETE /social/groups/{id}/members/{user_id}` | | 204: leave, or owner removes someone | 403 · 404 · 409 owner can't leave (delete the group) |
| `GET /social/groups/{id}/messages` | query `after` (timestamp, for polling), `limit` | `[{ id, sender, body, created_at, mine }]` oldest first | 404 |
| `POST /social/groups/{id}/messages` | `body` (1–2000) | 201 message | 404 · 429 (30/min) |
| `GET /social/feed` | query `before`, `limit` | posts from me, friends and my groups, newest first | |
| `POST /social/posts` | `kind`: `progress` (choose `share` from `study_minutes`, `tasks_completed`, `steps`, `workout_done`, `study_streak`, `balance_streak`, `fitness_streak`), `achievement` (`achievement_code` you have earned), or `text`; optional `text` (≤500) and `group_id` | 201 `Post` | 404 group · 422 unearned achievement / empty share · 429 (20/h) |
| `DELETE /social/posts/{id}` | | 204 | 404 (own posts only) |
| `POST` / `DELETE /social/posts/{id}/like` | | `Post` with `like_count`, `liked_by_me` | 404 if you can't see it |
| `GET /social/groups/{id}/challenges` · `POST` | `title`, `metric` (`study_minutes`/`study_sessions`/`steps`/`tasks_completed`/`workouts`), `target`, `start_date`, `end_date` (≤ 92 days after start) | `Challenge[]` · 201 | 404 · 422 |
| `GET /social/challenges/{id}` | | `{ …, joined, participant_count, group_total, leaderboard: [{ user, value, completed }] }` | 404 |
| `POST` / `DELETE /social/challenges/{id}/join` | | `Challenge`. Only people who joined are counted and shown | 404 |

## Calendar and account (Phase 4)

| Method & path | Auth | Result |
|---|---|---|
| `POST /integrations/calendar` | bearer | 201 `{ url, note }`: a private `…/calendar/<token>.ics` link (built from `PUBLIC_BASE_URL`). Creating a new one revokes the old one. Only a SHA-256 of the token is stored |
| `DELETE /integrations/calendar` | bearer | 204, link stops working |
| `GET /integrations/calendar/{token}.ics` | the token in the link | `text/calendar`: open tasks with due dates, upcoming exams, today's plan. 404 for unknown tokens; 120/h per IP; the token is redacted from access logs |
| `GET /account/export` | bearer | JSON with everything stored about the user (profile, tasks, study, activity, sleep, meals, plans, social). 5/h |

## Rate limits

| What | Limit (default) |
|---|---|
| Register | `AUTH_RATE_LIMIT_PER_MINUTE` per IP |
| Login | same, per IP + email |
| Change password, delete account | same, per user |
| AI plan generation, photo estimate | `AI_RATE_LIMIT_PER_HOUR` per user |
| Username lookup | 60/min · friend requests 30/h · chat 30/min · posts 20/h |
| Calendar feed | 120/h per IP · data export 5/h per user |

Limits are in memory (one instance). Put them behind Redis or the gateway before running several instances.
