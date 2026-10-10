# Backend ↔ frontend integration

How the OMNIA API is consumed by the one OMNIA frontend, the Flutter app in `Shehwaar/omnia_ui`. This file covers the server side of that contract. Client architecture, base-URL configuration and run instructions live with the frontend:

- [`Shehwaar/omnia_ui/integration/README.md`](../../Shehwaar/omnia_ui/integration/README.md): running the app against this backend
- [`Shehwaar/omnia_ui/integration/API_CONTRACT.md`](../../Shehwaar/omnia_ui/integration/API_CONTRACT.md): what the app sends and expects
- `START_OMNIA.bat` at the repository root: local launcher (Ollama, this backend, Android emulator, Flutter app)

An older Flutter app that used to live in `Fawaz/` (`Fawaz/lib`) has been removed. Do not build or copy from it.

## 1. Overview

```
Shehwaar/omnia_ui ─▶ HTTPS ─▶ FastAPI /api ─▶ PostgreSQL
                                   └▶ AI provider (server only)
```

The API base URL is the only configuration the app needs; it holds no secrets. Plain `http://` is for local development only; deployed backends should use HTTPS.

## 2. Authentication flow

1. **Register / sign in:** the app calls `POST /auth/register` (name, email, password, device timezone) or `POST /auth/login`. The response is `{access_token, user}`.
2. **Store:** the app keeps the token in the platform's secure store.
3. **Use:** every request carries `Authorization: Bearer <token>`.
4. **Restore on launch:** the app calls `GET /auth/me` with the stored token. A 401 means sign in again.
5. **Expiry:** tokens last 12 h by default. Any 401 on a signed-in request means the token is no longer valid.
6. **Sign out:** clears the token on the device. **Sign out on all devices** (`POST /auth/logout-all`) and **Change password** (`POST /auth/change-password`) bump the server-side token version, which invalidates every other token. Change password returns a fresh token for this device.
7. **Delete account:** `POST /auth/delete-account` with the password, then local sign-out.

The user id never comes from the app. The server reads it from the token, and request bodies containing `user_id` are rejected with 422.

## 3. Error handling

The backend always answers errors as `{"error": {"code", "message", "details"?, "request_id"?}}`. `message` is safe to show to users; `details` carries per-field validation messages; `code` is stable for programmatic handling (for example `replan_proposal_stale`). The server never returns stack traces or database messages.

## 4. AI planner

- The app only calls **our** backend (`/ai/daily-plan`, `/nutrition/estimate`). It contains no AI keys and never calls Anthropic or any other provider.
- `AI_PROVIDER=rules` (the default) uses a deterministic planner. With `anthropic` and `AI_API_KEY`, the server calls Claude. Any provider failure falls back to the rules planner, and the response shows `is_fallback: true`.
- What the provider receives: goals, today's and yesterday's totals, streak counts, last night's sleep, upcoming exam subject/title/days left, open task titles as `t1…` refs, and the user's note. It never receives email, name, ids or task notes.
- The plan adapts: a short or poor night (< 6 h or quality ≤ 2) splits study into shorter blocks, and the reason appears under **What changed?**. Study items carry `subject_id`, so opening one shows that subject's topics.
- Photo meal estimates need `AI_PROVIDER=anthropic`. Without it the API answers 503 and the app says photo analysis isn't set up, while manual meal logging works as usual.

## 5. Running everything locally

```bash
cp .env.example .env              # set POSTGRES_PASSWORD, AUTH_SECRET
docker compose up --build         # PostgreSQL + API on :8000, migrations run on start
docker compose exec backend python -m app.scripts.seed   # optional demo account
```

Then start the app from `Shehwaar/omnia_ui` (see its `integration/README.md`), or use `START_OMNIA.bat` at the repository root.

Demo account: `demo@omnia.app` / `omnia-demo-123` (friend `riya.demo@omnia.app`, same password). All demo data is fictional.

## 6. Testing the integration

| Level | Command | Covers |
|---|---|---|
| Backend unit + API | `cd backend && pytest` (add `TEST_DATABASE_URL=...` for PostgreSQL) | every endpoint, ownership, validation, rate limits, migrations, AI fallback |
| Live end-to-end | `python backend/scripts/integration_check.py --phase create`, restart the API, then `--phase verify` | the exact calls and JSON fields the frontend repositories use, cross-user isolation, and persistence across a restart |
| Frontend | `cd Shehwaar/omnia_ui && flutter test` | API client (headers, errors, 401, paging, task mapping), auth flows, token restore, each tab against an in-process fake backend |

## 7. Deploying

1. Provision PostgreSQL and set `DATABASE_URL`, `AUTH_SECRET`, `APP_ENV=production`, `PUBLIC_BASE_URL` and, for web builds, `CORS_ORIGINS`. Optionally set `AI_PROVIDER` and `AI_API_KEY`.
2. Run the backend container behind HTTPS. Migrations run on start (`alembic upgrade head`). In production the API refuses a weak secret or SQLite, turns off `/api/docs`, and sends HSTS.
3. Build the app from `Shehwaar/omnia_ui` with `--dart-define=API_BASE_URL=https://<your-api>/api`.
4. Store secrets in your host's secret manager, never in the repo or the app.

## 8. Troubleshooting

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
