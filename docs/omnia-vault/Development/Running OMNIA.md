---
type: development
---

# Running OMNIA

Short operational notes. The full instructions are in `Shehwaar/README.md` (frontend) and `Fawaz/README.md` (backend and Docker).

## Frontend (canonical)

```powershell
cd Shehwaar\omnia_ui
flutter pub get
flutter run -d <device>                                   # mock mode
flutter run -d <device> --dart-define=OMNIA_DATA=api      # API mode
flutter run -d <device> --dart-define=OMNIA_DATA=api --dart-define=API_BASE_URL=http://<lan-ip>:8000/api
```

Which URL is used when: see [[Mock vs API Mode]].

## Backend, local SQLite (Windows, as used for the auth checkpoint)

```powershell
cd Fawaz\backend
py -3.13 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
Copy-Item .env.example .env        # first time only
alembic upgrade head
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- Health: `http://localhost:8000/api/health/ready` should return `{"status":"ok","database":"ok"}`. Docs: `/api/docs` (outside production only).
- Set `AUTH_SECRET` in `.env` or every backend restart signs everyone out ([[Backend Overview]]).
- `Fawaz/backend/.env` and `omnia.db` exist locally and are git-ignored (`Fawaz/.gitignore`). Keep it that way.
- Optional demo data: `python -m app.scripts.seed`.

## Backend, Docker Compose (PostgreSQL)

`Fawaz/docker-compose.yml` runs `db` (postgres:16-alpine, not published) and `backend`. It requires `POSTGRES_PASSWORD` and `AUTH_SECRET` in `Fawaz/.env`. See `Fawaz/README.md`.

## Android emulator

The emulator reaches the host at `10.0.2.2`. Plain HTTP is allowed only in debug builds.

Related: [[Testing]] · [[Authentication Flow]]
