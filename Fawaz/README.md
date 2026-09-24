# OMNIA

One plan for study, tasks, fitness, sleep and food: a Flutter app (Shew's UI) backed by a FastAPI + PostgreSQL API that also generates an adaptive AI daily plan.

```
repo/
  lib/, test/, android/, ios/, web/, macos/, linux/, windows/   Flutter app (the product UI)
  backend/                                                      FastAPI API, migrations, tests
  docs/API.md            every endpoint, request and response
  docs/ARCHITECTURE.md   how the pieces fit, data model, security
  docs/INTEGRATION.md    how the app talks to the API; setup per platform; troubleshooting
  docker-compose.yml     PostgreSQL + API for local runs
```

## Quick start

You need Docker (or Python 3.11+ and PostgreSQL 14+) and the Flutter SDK (Dart ≥ 3.13).

### 1. Start the backend

```bash
cp .env.example .env
# edit .env: set POSTGRES_PASSWORD and AUTH_SECRET (generate one with the command in the file)
docker compose up --build
# optional demo data (fictional): demo@omnia.app / omnia-demo-123
docker compose exec backend python -m app.scripts.seed
```

Check it: <http://localhost:8000/api/health/ready> → `{"status":"ok","database":"ok"}`. API docs (development only): <http://localhost:8000/api/docs>.

Without Docker:

```bash
cd backend
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env          # set DATABASE_URL and AUTH_SECRET
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

### 2. Run the app

```bash
flutter pub get
flutter run                    # debug: Android emulator → 10.0.2.2:8000, others → localhost:8000
flutter run -d chrome          # web (dev CORS allows any localhost port)
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api   # a real phone on your Wi-Fi
```

Release builds have no default URL and must be built with `--dart-define=API_BASE_URL=https://your-api.example.com/api`. See [docs/INTEGRATION.md](docs/INTEGRATION.md) for each platform.

## Configuration

All secrets live in environment variables or an untracked `.env` file, never in code. The Flutter app holds **no** secrets, only the API URL.

| Variable | Needed | What it is |
|---|---|---|
| `DATABASE_URL` | production | `. Local dev falls back to SQLite. |
| `AUTH_SECRET` | production | 32+ random characters for signing tokens. `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `POSTGRES_PASSWORD` | docker compose | Password for the bundled database container. |
| `PUBLIC_BASE_URL` | for calendar links | Public URL of the API, e.g. `https://api.example.com`. |
| `AI_PROVIDER`, `AI_API_KEY`, `AI_MODEL` | optional | `rules` (default) works offline with no key. Set `anthropic` and a key from <https://console.anthropic.com/> for Claude plans and food-photo estimates. |
| `CORS_ORIGINS` | web builds | Comma-separated browser origins allowed in production. |

Full list with defaults: [`backend/.env.example`](backend/.env.example).

## Tests

```bash
# backend (SQLite in-memory; set TEST_DATABASE_URL to run on PostgreSQL)
cd backend && ruff check . && pytest
TEST_DATABASE_URL=postgresql+psycopg://omnia:***@localhost:5432/omnia_test pytest

# end-to-end against a running backend, including a restart
python scripts/integration_check.py --base http://localhost:8000/api --phase create
# restart the backend, then:
python scripts/integration_check.py --base http://localhost:8000/api --phase verify

# Flutter (widget and API-client tests use an in-process fake backend)
flutter analyze && flutter test
```

CI (`.github/workflows/ci.yml`) runs the backend suite on SQLite and PostgreSQL, checks migrations, and runs `flutter analyze` and `flutter test`.

## Features

- **Account:** register, sign in, token kept in the platform's secure storage and restored on launch, change password, sign out everywhere, JSON data export, delete account.
- **Today:** dashboard of study minutes, tasks, steps, workout, sleep and calories against your goals, streaks, next exam and upcoming tasks.
- **Plan:** AI daily plan with an optional note ("slept badly"), regenerate, "what changed" adjustments and tips; adapts to last night's sleep. Study blocks open a revision page with topics from your backlog, a focus timer, and time logging.
- **Tasks:** create, edit, complete, delete, with due date/time, estimate, category and priority.
- **Study:** subjects, exams, backlog/revision topics, sessions and a 7-day study plan.
- **Track:** steps and workouts, sleep, meals (with an optional photo estimate when AI is configured).
- **Insights:** streaks, 14-day history and achievements.
- **Social:** friends by username, groups with chat, challenges with leaderboards, a feed of progress posts.
- **Calendar:** private iCalendar link with tasks, exams and today's plan.

## Security

Passwords are hashed with scrypt; tokens are short-lived, signed JWTs that are invalidated by password change or "sign out everywhere". Every query is scoped to the signed-in user, and other users' data returns 404. Requests reject unknown fields such as `user_id`. Sensitive endpoints are rate limited, and errors never include stack traces or database messages. Logs never contain passwords or tokens. The AI provider key stays on the server and only a minimal, anonymised context is sent to it. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#security).
