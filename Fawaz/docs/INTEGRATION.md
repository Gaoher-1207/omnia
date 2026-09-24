# Flutter ↔ backend integration

How Shew's Flutter app talks to the OMNIA API: configuration, auth, data flow per screen, errors and troubleshooting. The UI design is unchanged. Only the data layer behind it moved from in-memory mocks to the real API.

## 1. Overview

```
Flutter screen ─▶ controller / Loadable ─▶ repository ─▶ ApiClient ─▶ HTTPS ─▶ FastAPI /api ─▶ PostgreSQL
                                                                                   └▶ AI provider (server only)
```

| Layer | Where | Job |
|---|---|---|
| `ApiConfig` | `lib/core/api/api_config.dart` | Picks the base URL |
| `ApiClient` | `lib/core/api/api_client.dart` | JSON over `package:http`, bearer header, timeouts, error mapping, 401 broadcast |
| `ApiException` | `lib/core/api/api_exception.dart` | One error type; `friendlyError()` turns it into a user message |
| `TokenStore` | `lib/core/auth/token_store.dart` | Secure token persistence |
| `AuthController` / `AuthScope` | `lib/core/auth/auth_controller.dart` | Sign-in state: `unknown → signedOut / signedIn` |
| `AppDependencies` | `lib/core/app_dependencies.dart` | Builds every repository from one `ApiClient`; tests inject a fake |
| Repositories | `lib/features/*/data/` | One per feature; the only code that knows endpoint paths and JSON keys |
| `SessionScope` | `lib/core/session.dart` | Per-user state (tasks, today's plan, dashboard), rebuilt on every sign-in |

The mock repositories (`core/data/*`, `mock_task_repository`, `mock_goal_repository`, mock study data) have been removed. No screen shows sample data.

## 2. Base URL per platform

`API_BASE_URL` is a compile-time `--dart-define`. It is not a secret.

| Where the app runs | Command | URL used |
|---|---|---|
| Android emulator (debug) | `flutter run` | `http://10.0.2.2:8000/api`, the emulator's alias for your computer |
| iOS simulator, desktop, web (debug) | `flutter run` / `flutter run -d chrome` | `http://localhost:8000/api` |
| Physical phone on your Wi-Fi | `flutter run --dart-define=API_BASE_URL=http://<your-computer-LAN-IP>:8000/api` | as given; run uvicorn with `--host 0.0.0.0` |
| Any release build | `flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api` | as given; **required**, otherwise the app shows a configuration screen |

Plain `http://` is only allowed in debug builds. The Android debug manifest sets `usesCleartextTraffic`, and iOS allows local networking. Release builds should use HTTPS.

## 3. Authentication flow

1. **Register / sign in:** `AuthPage` calls `POST /auth/register` (name, email, password, device timezone) or `POST /auth/login`. The response is `{access_token, user}`.
2. **Store:** the token goes to `SecureTokenStore`: Keychain on iOS/macOS, Keystore-backed storage on Android, libsecret on Linux, DPAPI on Windows, and browser storage on web. If the platform store fails, the token is kept in memory only, so the user is asked to sign in again after a restart.
3. **Use:** `ApiClient` adds `Authorization: Bearer <token>` to every request.
4. **Restore on launch:** `AuthController.restore()` reads the token and calls `GET /auth/me`. If that succeeds the user goes straight to Today. A 401 returns them to sign-in. A network failure shows *Couldn't reach OMNIA* with a retry button and keeps the token.
5. **Expiry:** tokens last 12 h by default. Any 401 on a signed-in request clears the token, broadcasts `onUnauthorized`, and the app returns to sign-in with *Your session ended. Please sign in again.*
6. **Sign out:** clears the token locally. **Sign out on all devices** (`POST /auth/logout-all`) and **Change password** (`POST /auth/change-password`) bump the server-side token version, which invalidates every other token. Change password returns a fresh token for this device.
7. **Delete account:** `POST /auth/delete-account` with the password, then local sign-out.

The user id never comes from the app. The server reads it from the token, and request bodies containing `user_id` are rejected with 422.

## 4. Screen → endpoint map

| Screen | Repository | Endpoints |
|---|---|---|
| Onboarding → Sign in / Create account | `AuthController` | `POST /auth/register`, `POST /auth/login`, `GET /auth/me` |
| Today (`home_page`) | `DashboardRepository` | `GET /dashboard` (one call: totals, goals, streaks, next exam, upcoming tasks, today's AI plan) |
| Plan (`plan_page`) | `PlanRepository` | `GET /ai/daily-plan`, `POST /ai/daily-plan {note, regenerate}` |
| Study block (`revision_detail_page`) | `StudyRepository` | `GET /study/backlog?subject_id=`, `PATCH /study/backlog/{id}`, `POST /study/backlog`, `POST /study/sessions`, `DELETE /study/sessions/{id}` (undo), `GET /study/exams` |
| Focus timer | `StudyRepository` | `POST /study/sessions` with the minutes actually focused |
| Tasks | `ApiTaskRepository` | `GET /tasks` (pages through all), `POST`, `PATCH`, `DELETE /tasks/{id}` |
| Study (`study_page`) | `StudyRepository` | subjects, exams, backlog, sessions CRUD; `GET /study/plan?days=7` |
| Track | `TrackRepository` | `GET /activity`, `PUT /activity/{day}`, `GET/PUT/DELETE /sleep/{day}`, `GET /sleep`, meals CRUD, `GET /nutrition/summary`, `POST /nutrition/estimate` |
| Insights | `ProgressRepository` | `GET /progress?days=14`, `GET /achievements` |
| Goals (Settings) | `AuthController.updateProfile` | `PATCH /profile` (goals, timezone, username) |
| Social / group | `SocialRepository` | `/social/*`: friends, requests, groups, messages (polled), challenges, feed, posts, likes |
| Settings | various | `POST/DELETE /integrations/calendar`, `GET /account/export`, change password, sign out everywhere, delete account |

Field mapping kept out of the widgets:

- Task priority: app `high/normal/low` ↔ API `high/medium/low`.
- Task due: app `dueAt` (DateTime) ↔ API `due_date` + optional `due_time`. A time of exactly midnight means "no time".
- Task estimate: `Duration` ↔ `estimated_minutes`. Category: `OmniaCategory.name` ↔ `category`.
- Dates are `YYYY-MM-DD` in the user's timezone (`formatDay` / `parseDay` in `core/models/user.dart`).

## 5. Loading, empty, error and retry states

Every screen loads through `Loadable<T>` / `ControllerScope` and renders one of these:

| State | Widget | Example |
|---|---|---|
| Loading | `LoadingView` | spinner in place of content |
| Empty | `MessageView` | "No plan for today yet", "Add your subjects first", "No exams coming up." |
| Error | `ErrorView` with **Try again** | "Couldn't load your day", plus the friendly reason |
| Action failed | `showError` snackbar; the form stays filled in | "You already have a subject with this name" |

After a change, the affected screen reloads from the server rather than guessing (for example, `SessionScope.refreshDashboard` after logging study time).

## 6. Error handling

The backend always answers errors as `{"error": {"code", "message", "details"?, "request_id"?}}`. `ApiClient` maps that to `ApiException`:

| Case | `ApiException` | What the user sees |
|---|---|---|
| No connection / DNS / timeout (20 s) | `isNetwork` (status 0) | "Can't reach OMNIA right now. Check your connection and try again." |
| 401 | `isUnauthorized` | back to sign-in (section 3) |
| 503 on photo estimate | `isUnavailable` | "Photo analysis isn't set up on this server. Log the meal by hand." |
| Any other 4xx/5xx | `code` + server `message`; field errors via `fieldMessage('title')` | the server's human message, under the matching form field or in a snackbar (for example "You already have a subject with this name", "Incorrect email or password") |
| Non-API exception | n/a | "Something went wrong. Please try again." |

The server never returns stack traces or database messages, and the app never shows raw exceptions.

## 7. AI planner

- The app only calls **our** backend (`/ai/daily-plan`, `/nutrition/estimate`). It contains no AI keys and never calls Anthropic or any other provider.
- `AI_PROVIDER=rules` (the default) uses a deterministic planner. With `anthropic` and `AI_API_KEY`, the server calls Claude. Any provider failure falls back to the rules planner, and the response shows `is_fallback: true`.
- What the provider receives: goals, today's and yesterday's totals, streak counts, last night's sleep, upcoming exam subject/title/days left, open task titles as `t1…` refs, and the user's note. It never receives email, name, ids or task notes.
- The plan adapts: a short or poor night (< 6 h or quality ≤ 2) splits study into shorter blocks, and the reason appears under **What changed?**. Study items carry `subject_id`, so opening one shows that subject's topics.
- Photo meal estimates need `AI_PROVIDER=anthropic`. Without it the API answers 503 and the app says photo analysis isn't set up, while manual meal logging works as usual.

## 8. Running everything locally

```bash
cp .env.example .env              # set POSTGRES_PASSWORD, AUTH_SECRET
docker compose up --build         # PostgreSQL + API on :8000, migrations run on start
docker compose exec backend python -m app.scripts.seed   # optional demo account
flutter pub get
flutter run                       # or -d chrome / --dart-define=API_BASE_URL=...
```

Demo account: `demo@omnia.app` / `omnia-demo-123` (friend `riya.demo@omnia.app`, same password). All demo data is fictional.

## 9. Testing the integration

| Level | Command | Covers |
|---|---|---|
| Backend unit + API | `cd backend && pytest` (add `TEST_DATABASE_URL=...` for PostgreSQL) | every endpoint, ownership, validation, rate limits, migrations, AI fallback |
| Live end-to-end | `python backend/scripts/integration_check.py --phase create`, restart the API, then `--phase verify` | the exact calls and JSON fields the Flutter repositories use, cross-user isolation, and persistence across a restart |
| Flutter | `flutter test` | API client (headers, errors, 401, paging, task mapping), auth flows, token restore, each tab against an in-process fake backend |

## 10. Deploying

1. Provision PostgreSQL and set `DATABASE_URL`, `AUTH_SECRET`, `APP_ENV=production`, `PUBLIC_BASE_URL` and, for web builds, `CORS_ORIGINS`. Optionally set `AI_PROVIDER` and `AI_API_KEY`.
2. Run the backend container behind HTTPS. Migrations run on start (`alembic upgrade head`). In production the API refuses a weak secret or SQLite, turns off `/api/docs`, and sends HSTS.
3. Build the app with `--dart-define=API_BASE_URL=https://<your-api>/api`.
4. Store secrets in your host's secret manager, never in the repo or the app.

## 11. Troubleshooting

| Symptom | Fix |
|---|---|
| "Couldn't reach OMNIA" on the Android emulator | Backend not on port 8000, or you used `localhost`. The emulator needs `10.0.2.2` (the default). |
| Works on the emulator, not on a real phone | Pass your computer's LAN IP via `API_BASE_URL`; start uvicorn with `--host 0.0.0.0`; allow port 8000 in the firewall. |
| Web: CORS error in the browser console | In development any `localhost` port is allowed. In production, add the site's origin to `CORS_ORIGINS`. |
| Release build shows "Server not configured" | Rebuild with `--dart-define=API_BASE_URL=...`. |
| Signed out after every restart (Linux) | Install libsecret (`sudo apt install libsecret-1-dev gnome-keyring`). Otherwise the token is kept in memory only. |
| Everyone is signed out whenever the dev server restarts | `AUTH_SECRET` is empty, so development uses a temporary secret. Set one in `backend/.env`. |
| Timezone validation error on sign-up | The backend accepts IANA names and common aliases (for example `Asia/Calcutta`). Pick your timezone in Goals if the device reports something unusual. |
| Calendar link points to localhost | Set `PUBLIC_BASE_URL`. |
| "Photo analysis isn't set up on this server" | Expected without `AI_PROVIDER=anthropic` and `AI_API_KEY`. |
| AI plan says `is_fallback: true` | The provider failed or timed out. Check the server logs (no keys or tokens are logged). |
