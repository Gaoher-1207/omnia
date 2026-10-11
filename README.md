# OMNIA

**Everything. One plan.**

OMNIA is an AI-assisted personal planning app that brings study, tasks, activity, sleep and focus into one daily system. Instead of treating each area as a separate tracker, it uses their shared context to suggest a realistic plan for the day, records what actually happened, and can safely adapt the plan when life changes.

![Flutter](https://img.shields.io/badge/Flutter-3.47-54C5F8?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688?logo=fastapi&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)

## What works today

In API mode (signed in against the backend), these are real end to end:

- **Daily plan.** Generate a suggested plan (AI-assisted, with a deterministic rules fallback) that fits your planning hours and fixed commitments, and see why it looks the way it does.
- **Manual plan items.** Add a task, study subject, goal, workout, rest block or custom item from the Plan page. Choose it from dropdowns, set its date, start time and duration, and the app checks for conflicts without moving other blocks. Hold a plan item's status square and confirm to remove that plan block; linked tasks, subjects and logged study time are kept. Fixed commitments cannot be removed this way.
- **Check-offs.** Each plan block has a check-off square: done ✓, partly done –, not done ×. A study block marked done counts as study time for its subject and planned length; partly done counts only the minutes you give. Focus time already inside the block is never counted twice.
- **Adaptive replanning.** Ask for a change in plain language, preview it, and apply it explicitly. See [below](#adaptive-replanning).
- **Ask OmniAI.** A floating button on every main tab opens a context-aware, read-only assistant. When you ask it to change today's plan, it offers the same validated preview; only your Apply changes anything.
- **Tasks, long-term goals, study subjects and exams, and fixed commitments**, all saved to your account.
- **Activity and sleep logging.** Steps and workouts, and sleep chosen on hour/minute wheels.
- **Focus timer.** Each finished Focus phase is saved as study time.
- **Insights.** Week and month habit grids for workouts, steps and study, built only from days you actually logged. Unlogged days are never counted as zero.
- **Accounts.** Sign-up and sign-in, tokens kept in the device's secure storage, owner-scoped data, password change, sign-out everywhere and account deletion.
- **Interface.** A neo-brutalist Flutter UI in light and dark themes, tested at narrow widths and 200% text, with reduced-motion support.

Without a backend, `flutter run` starts a **mock mode** with a labelled sample day for UI work.

The backend also has modules the app doesn't use yet: meals and nutrition, progress and streaks, achievements, social (friends, groups, challenges) and calendar feeds. See [Project status](#project-status).

## Adaptive replanning

Replanning is a reviewable transaction, not an invisible AI edit:

1. You ask for a change, such as _"Skip my workout and add revision time."_ (from Plan's **Adjust today's plan**, or from Ask OmniAI).
2. The backend creates a temporary proposal without changing the active plan.
3. The app shows only the useful differences:

   ```text
   Removed Evening Workout
   Added Revision
   ```

4. You apply or cancel the proposal. Closing the preview cancels it.
5. Applying creates a new, immutable plan revision.

Behind the compact preview, the backend still does ownership checks, expiry and stale-state detection, context fingerprinting, schedule validation, operation replay and concurrency locking. A failed, expired, dismissed or outdated proposal never changes the plan. Recorded check-offs are part of that context: work marked done isn't planned again, and checking something off makes an open proposal stale.

Operations are `ADD`, `REMOVE`, `MOVE`, `RESCHEDULE`, `SHORTEN` and `UNCHANGED`; unchanged items are hidden from the interface.

## Architecture

```mermaid
flowchart LR
    APP["Flutter app\nShehwaar/omnia_ui"] -->|JSON over HTTPS| API["FastAPI API\nFawaz/backend"]
    API --> AUTH["Authentication and\nowner-scoped services"]
    API --> PLAN["Planner, proposals,\noutcomes and validation"]
    API --> DB[("SQLite in development\nPostgreSQL in production")]
    PLAN --> PROVIDERS["Rules · Ollama\nOpenRouter · Anthropic"]
```

The app holds no AI provider secrets. It talks only to the OMNIA API, and provider selection and credentials stay on the server.

## Repository layout

```text
omnia/
├── Shehwaar/
│   └── omnia_ui/            # The Flutter app (the only frontend)
├── Fawaz/
│   ├── backend/             # FastAPI app, Alembic migrations, tests
│   ├── docs/                # API reference, architecture, integration, operations
│   └── docker-compose.yml   # PostgreSQL + migrate step + API
├── .github/workflows/ci.yml # CI for the backend and the Flutter app
├── docs/omnia-vault/        # Product, architecture, status and roadmap notes (Obsidian)
├── Gaoher/                  # AI design notes and an experimental AI package (not wired into the backend)
├── Ibrahim/                 # Cloud/DevOps notes and an older compose draft (not used)
├── Ausaaf/, Rahman/, Umair/ # Security and cloud-security role notes
└── START_OMNIA.bat          # One-click Windows development launcher
```

`Fawaz/` is backend-only; the older Flutter app that used to live there has been removed. The supported way to run the backend is `Fawaz/backend` (directly or with `Fawaz/docker-compose.yml`), and the only app is [`Shehwaar/omnia_ui`](Shehwaar/omnia_ui).

## Quick start

### One-click Windows development

The launcher starts or reuses Ollama, runs database migrations, starts the backend, opens the configured Android emulator and runs the Flutter app.

Prerequisites:

- Flutter with Android tooling
- Python 3.11+ and the backend virtual environment
- An Android Virtual Device
- Ollama and an installed model, for the local assistant

Copy the launcher configuration and edit its paths and model for your machine:

```powershell
Copy-Item .\Shehwaar\omnia_ui\integration\launcher.env.example `
  .\Shehwaar\omnia_ui\integration\.env.launcher
```

Run the preflight check (it changes nothing):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\Shehwaar\omnia_ui\integration\start_omnia.ps1 -Role Check
```

Then double-click `START_OMNIA.bat`, or run `.\START_OMNIA.bat`. The launcher is documented in [`LAUNCHER.md`](Shehwaar/omnia_ui/integration/LAUNCHER.md).

### Backend by hand (Windows)

```powershell
cd .\Fawaz\backend
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

`python.exe -m alembic` avoids needing a global `alembic` command. Run the migration step again after pulling changes that add migrations.

The local backend uses SQLite by default. Once it is running:

- Health: <http://localhost:8000/api/health/ready>
- API documentation (development only): <http://localhost:8000/api/docs>

### The Flutter app

In another terminal:

```powershell
cd .\Shehwaar\omnia_ui
flutter pub get
flutter run --dart-define=OMNIA_DATA=api
```

Debug builds use `http://10.0.2.2:8000/api` on the Android emulator and `http://localhost:8000/api` on desktop, iOS and web. For UI work without a backend or sign-in, use plain `flutter run` (mock mode).

### Docker backend

```powershell
cd .\Fawaz
Copy-Item .env.example .env
# Set POSTGRES_PASSWORD and a 32+ character AUTH_SECRET in .env
docker compose up --build
```

Compose runs a one-off `migrate` step before the API starts; the API container never migrates on its own. Optional fictional demo data:

```powershell
docker compose exec backend python -m app.scripts.seed
```

## Configuration

Backend settings belong in an untracked `Fawaz/backend/.env` for local Python runs, or `Fawaz/.env` for Docker Compose. Start from the matching `.env.example`.

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | SQLite for local development, PostgreSQL in production |
| `AUTH_SECRET` | Signs access tokens; at least 32 random characters in production |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Token lifetime (default 720, i.e. 12 hours) |
| `PLANNER_AI_PROVIDER` | Daily planner and plan adjustments: `rules`, `ollama` (local demo), `openrouter` (deployment) or `anthropic` |
| `REPLAN_TIMEOUT_SECONDS` | Time limit for one plan adjustment, including one retry and the rules fallback (default 45) |
| `ASSISTANT_PROVIDER` | Ask OmniAI: `off`, `ollama` or `openrouter` |
| `ASSISTANT_BASE_URL`, `ASSISTANT_MODEL` | Local Ollama-compatible endpoint and model |
| `OPENROUTER_API_KEY` | Optional server-side OpenRouter credential |
| `AI_API_KEY` | Optional server-side Anthropic credential |
| `CORS_ORIGINS` | Browser origins allowed to call the API in production |
| `PUBLIC_BASE_URL` | Public API URL for generated calendar links |

The full list with defaults is in [`Fawaz/backend/.env.example`](Fawaz/backend/.env.example). Never commit real `.env` files, tokens or provider keys.

## Testing

Backend (from `Fawaz/backend`):

```powershell
.\.venv\Scripts\python.exe -m ruff check app tests alembic scripts
.\.venv\Scripts\python.exe -m ruff format --check app tests alembic scripts
.\.venv\Scripts\python.exe -m pytest
# Against PostgreSQL:
$env:TEST_DATABASE_URL = "postgresql+psycopg://user:pass@localhost:5432/omnia_test"; .\.venv\Scripts\python.exe -m pytest
```

The backend suite runs on a frozen clock (`tests/conftest.py`), so results don't depend on the machine's timezone or time of day.

Flutter (from `Shehwaar/omnia_ui`):

```powershell
flutter analyze
flutter test
```

The suites cover authentication and ownership isolation, migrations (including PostgreSQL defaults), planner fallback, the proposal lifecycle, check-offs and study credit, API mapping, accessibility, narrow and large-text layouts, and light and dark themes.

**CI.** [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to `main` and every pull request:

- **Backend:** Ruff (lint and format), the tests on SQLite and on PostgreSQL 16, and migrations up → check → down → up on both databases.
- **App:** `flutter analyze`, `flutter test` and a web release build.

Any failing step fails the run.

## Documentation

- [Flutter app guide](Shehwaar/README.md) and [integration guide](Shehwaar/omnia_ui/integration/README.md) / [API contract (app view)](Shehwaar/omnia_ui/integration/API_CONTRACT.md)
- [Backend README](Fawaz/README.md), [API reference](Fawaz/docs/API.md), [architecture](Fawaz/docs/ARCHITECTURE.md), [integration](Fawaz/docs/INTEGRATION.md)
- [Operations: releases, migrations, rollback, backups, secrets, monitoring](Fawaz/docs/OPERATIONS.md)
- [Adaptive replanning contract](Fawaz/backend/docs/adaptive-replanning.md)
- [Product and architecture vault](docs/omnia-vault/00%20-%20OMNIA.md), [current status](docs/omnia-vault/Current%20Status.md) and [roadmap](docs/omnia-vault/Roadmap/Roadmap.md)

## Development notes

- Run migrations before starting the API (`python -m alembic upgrade head` from `Fawaz/backend` with its virtual-environment Python). The launcher and `docker compose` do this for you.
- Android emulators reach the host through `10.0.2.2`, not `localhost`.
- Keep several gigabytes free on the system drive for Flutter, Gradle and emulator builds.
- The rules planner works without any AI key; optional providers are configured only on the backend.

## Project status

OMNIA is under active development as a final-year team project. The [roadmap](docs/omnia-vault/Roadmap/Roadmap.md) is the source of truth; in short:

| Area | Status |
|---|---|
| Accounts, tasks, goals, study subjects and exams, commitments | Saved to the account |
| Daily plan, check-offs with study credit, adaptive replanning | Saved to the account |
| Activity, sleep, Focus study time, Insights (workouts, steps, study) | Saved to the account |
| Ask OmniAI | Read-only assistant; can open the replan preview |
| Onboarding | Two-page intro; completion remembered on the device |
| Nutrition, progress/streak views, achievements, social, calendar feeds | Backend only; not in the app yet |
| Release | CI defined but not yet green on GitHub; Android application ID and signing not set up; hosted error reporting not configured; in-memory rate limiter (single instance only) |
