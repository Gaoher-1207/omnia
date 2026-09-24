# OMNIA architecture

## Shape

One modular backend (no microservices) and one Flutter client (Shew's app, for Android, iOS, web and desktop), as the role guide asks. Phases 1–4 are all in the same deployable.

```
Flutter app      ──/api──▶  FastAPI app
                              │  request id · CORS · security headers
                              ▼
                           Auth (JWT bearer) ─▶ Validation (Pydantic)
                              ▼
                           Module service (business rules, ownership checks)
                              ├──▶ PostgreSQL via SQLAlchemy (Alembic migrations)
                              └──▶ AI provider interface ─▶ rules planner (default)
                                                         └▶ Claude API (optional, server-side key:
                                                            daily plan + food-photo estimate)
```

## Backend layout

```
backend/app/
  core/        config, security (hashing, JWT), errors, logging, rate limit, time
  db/          engine/session, declarative base, UTC datetime type
  common/      shared deps (DbSession, CurrentUser), ownership helper, schema helpers
  modules/
    auth/      register, login, me, change-password, logout-all, delete-account
    users/     User + Profile models, profile routes
    tasks/     to-dos
    study/     subjects, exams, backlog, sessions, planner.py (pure)
    activity/  daily steps / workouts
    sleep/     nightly sleep logs
    nutrition/ meals, daily summary, estimator.py (photo → estimate, not stored)
    progress/  streaks.py and achievements.py (pure), progress + achievements routes
    social/    friends, groups, chat, posts/likes, challenges
    integrations/ private calendar feed (ics.py), account export
    dashboard/ one-call Today screen
    ai/        context builder, providers (rules, Anthropic), plan storage
  scripts/seed.py   fictional demo account
```

Each module has the same pieces: `models.py`, `schemas.py`, `service.py`, `router.py`. Routers stay thin; rules live in services or in pure modules (`planner.py`, `streaks.py`, `providers.py`) that are unit-tested without a database.

## Flutter client layout

```
lib/
  core/api/        ApiConfig (base URL), ApiClient (http + bearer + error envelope), ApiException
  core/auth/       TokenStore (flutter_secure_storage), AuthController / AuthScope
  core/state/      Loadable<T>, ControllerScope<T>: loading / error / data for every screen
  core/session.dart per-user scope (tasks, today's plan, dashboard), rebuilt on each sign-in
  core/app_dependencies.dart  wires one ApiClient into every repository; tests inject a fake
  features/<name>/data/       repositories: the only code that knows endpoints and JSON keys
  features/<name>/domain/     immutable models used by the widgets
  features/<name>/*.dart      Shew's screens, now reading from repositories instead of mocks
```

Sign-in state lives above `MaterialApp`, so signing in or out swaps the whole tree and no screen can keep another user's data. Details: [INTEGRATION.md](INTEGRATION.md).

## Data model

| Table | Key columns | Notes |
|---|---|---|
| users | email (unique), password_hash | credentials only |
| profiles | user_id (PK/FK), display_name, timezone, goals, preferred_workout_time | 1:1 with users |
| tasks | user_id, title, priority, status, due_date, completed_at | idx (user, status, due), (user, completed_at) |
| subjects | user_id, name, color | unique (user, name) |
| exams | user_id, subject_id, title, exam_date | idx (user, exam_date) |
| backlog_items | user_id, subject_id, title, kind, status, estimated_minutes | idx (user, status) |
| study_sessions | user_id, subject_id?, backlog_item_id?, session_date, duration_minutes | idx (user, date); subject delete → NULL |
| activity_days | user_id, day, steps, workout_* | unique (user, day) |
| ai_plans | user_id, plan_date, source, is_fallback, fallback_reason, content (JSON) | history kept for adaptation |
| sleep_logs | user_id, day, duration_minutes, quality, bedtime, wake_time | unique (user, day) |
| meals | user_id, day, meal_type, description, calories, macros, source | idx (user, day) |
| friendships | requester_id, addressee_id, status | one row per pair |
| social_groups, group_members | owner, name / group, user, role | members must be the owner's friends |
| group_messages | group_id, sender_id, body, created_at | polled with `after` |
| posts, post_likes | author, kind, body, payload (server-computed numbers), visibility, group | |
| challenges, challenge_participants | group, metric, target, dates / user | only participants are counted |
| calendar_feeds | user_id, token_hash (SHA-256) | the raw token is never stored |

`users.token_version` is embedded in every token; bumping it (password change, sign out everywhere) revokes all older tokens. Profiles also hold `username` (unique), sleep and calorie goals. Migrations: `0001` initial → `0002` sleep/meals → `0003` social → `0004` calendar feeds.

All child rows cascade on user delete (`POST /auth/delete-account`). Check constraints back up the API validation. Streaks are computed, not stored, so they can't drift.

## Security

- scrypt password hashing (stdlib); login answers identically for unknown email vs wrong password.
- HS256 JWT, 12 h default lifetime (`ACCESS_TOKEN_EXPIRE_MINUTES`), secret from `AUTH_SECRET`, with a `ver` claim checked against `users.token_version`. The app refuses to start in production without a 32+ character secret or on SQLite.
- The Flutter app keeps the token in the OS secure store (Keychain / Keystore / libsecret / DPAPI) and holds no other secrets.
- Every query is filtered by the token's user id; foreign ids answer 404.
- Request bodies reject unknown fields (so `user_id` can't be smuggled in); ORM-only queries (no string SQL); bodies over `MAX_REQUEST_BYTES` get 413; uploaded photos are size- and magic-byte-checked and never stored.
- Social data exposes only `PublicUser`; post numbers are computed server-side; group members must be friends; challenge totals include only people who joined.
- Rate limits: login/register per IP (and email), password actions per user, AI plan and photo estimate per user, social writes, calendar feed and export (full table in API.md).
- Generic 500s; validation errors never echo input; logs hold method/path/status/request id only; calendar tokens are redacted and uvicorn's own access log is off.
- CORS allow-list from `CORS_ORIGINS` (plus any `localhost` port in development only, for `flutter run -d chrome`); `nosniff`, `no-referrer`, `DENY` framing headers; HSTS in production.
- OpenAPI docs are off in production.

## Decisions for the team to confirm

The role guide says stack and architecture need team agreement. These are the choices made to get a working MVP, each easy to change:

| # | Decision | Why | Owner to confirm |
|---|---|---|---|
| 1 | Python 3.11+, FastAPI, SQLAlchemy 2, Alembic, Pydantic 2 | typed, well documented, easy for AI contributors in Python | whole team |
| 2 | PostgreSQL in prod, SQLite allowed for local dev/tests | zero-setup local runs; CI runs both | Ibrahim |
| 3 | Access token only (no refresh token), kept in the OS secure store; revocable via `token_version` | simplest working flow; users re-sign-in after 12 h. Option: short access + refresh tokens | Rahaman, Ausaaf |
| 4 | scrypt instead of argon2/bcrypt | no native dependency; OWASP-listed | Rahaman, Ausaaf |
| 5 | Register returns 409 for an existing email | clearer UX, but reveals that the account exists | Rahaman, Ausaaf |
| 6 | In-memory rate limiter | fine for one instance; needs Redis/gateway when scaled | Ibrahim |
| 7 | Resources returned without a `{success,data}` envelope; one error envelope | idiomatic for FastAPI/OpenAPI typing; consistent errors | Shew |
| 8 | Rule-based planner as default and fallback; Claude API optional | works offline and free; AI failures never break the app | Gaoher + AI contributors |
| 9 | Streak and planner rules (see API.md) | first reasonable version | product discussion |
| 10 | Flutter state with InheritedNotifier scopes (no Provider/Riverpod/Bloc) and `package:http` | matches Shew's existing code; no new state library to learn | Shew |
| 11 | Group chat by polling (`after=`) instead of WebSockets | works everywhere, no extra infrastructure; switch if chat grows | Shew, Ibrahim |
| 12 | Photo estimates are never stored; the user confirms and saves a normal meal | privacy and accuracy | Gaoher, Rahaman |

## Next steps

- Refresh tokens and push notifications (plan reminders).
- Shared rate limiter (Redis) before running more than one backend instance.
- Photo storage only if the team decides users want a meal photo history (currently nothing is kept).
