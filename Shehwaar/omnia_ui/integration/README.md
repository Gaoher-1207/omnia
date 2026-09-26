# Running the OMNIA frontend against a backend

`Shehwaar/omnia_ui` is the one canonical OMNIA frontend. It runs on its own mock data, or against **any backend that implements the [OMNIA API contract](API_CONTRACT.md)**: the reference FastAPI backend in `Fawaz/backend`, a teammate's copy, or a deployed server. There is no second copy of the app for integration; point this one at a different URL.

| File | What it's for |
|---|---|
| [`API_CONTRACT.md`](API_CONTRACT.md) | Every endpoint the frontend calls, and the JSON it sends and expects |
| [`COMPATIBILITY.md`](COMPATIBILITY.md) | A checklist for confirming a backend works with this frontend |
| [`omnia.env.example`](omnia.env.example) | The settings, as a file for `--dart-define-from-file` |
| [`run_frontend.ps1`](run_frontend.ps1) | A Windows helper that builds the `flutter run` command and checks the backend first |

## Two modes

| | Mock mode (default) | API mode |
|---|---|---|
| Turned on by | nothing | `OMNIA_DATA=api` |
| Backend needed | no | yes |
| Sign-in | none; one local user | real accounts (register, sign in, sign out) |
| Tasks, profile and daily targets, day summary, activity and sleep | in-memory, seeded with a labelled **sample day** | the backend, per signed-in user |
| Long-term Goals | in-memory sample goals | in-memory, **starts empty** (no Goals endpoint yet); the screen says it isn't synced |
| Plan, Insights, Today's "Next up" | labelled sample content | empty states; never sample data |
| Focus timer | local | local |
| Used for | UI work, demos, automated tests | integration and real use |

Mock mode never makes a network call. API mode never shows sample data. Both use exactly the same screens and controllers; only the repositories behind them differ (`lib/core/app_dependencies.dart`).

## Settings

Both are **build-time** Flutter defines (`String.fromEnvironment`), not runtime environment variables. Change them and restart `flutter run`.

| Setting | Values | Default |
|---|---|---|
| `OMNIA_DATA` | `api`, or unset for mock mode | mock mode |
| `OMNIA_API_BASE_URL` | the API root, **including `/api`**, e.g. `http://192.168.1.20:8000/api` | see below |

`API_BASE_URL`, the older name, still works when `OMNIA_API_BASE_URL` is unset.

When no URL is given (resolved in `lib/core/api/api_config.dart`, the only place the app decides it; repositories only pass paths such as `/tasks`):

| Build | URL |
|---|---|
| Debug, Android emulator | `http://10.0.2.2:8000/api` (the emulator's name for your computer) |
| Debug, everything else (web, Windows, Linux, macOS, iOS) | `http://localhost:8000/api` |
| Release | **none**: the app shows "Server not configured" until built with `OMNIA_API_BASE_URL` |

A trailing `/` is removed.

### Platform notes

| Platform | Plain `http://` backend | Notes |
|---|---|---|
| Android | debug builds only (cleartext is enabled in the debug manifest) | release builds need `https://` |
| Windows, Linux | yes | |
| Web | yes | the backend must allow the page's origin (CORS). The reference backend allows only `CORS_ORIGINS` (default `http://localhost:5173`), so run `flutter run -d chrome --web-port 5173 …` or add your origin to `CORS_ORIGINS` |
| iOS | **not configured**: no App Transport Security exception | use `https://`, or add an ATS exception for development |
| macOS | **not configured**: the app has no outgoing-network entitlement (`com.apple.security.network.client`) | add it before using API mode on macOS |

iOS and macOS API mode have not been tested.

## Commands

From `Shehwaar/omnia_ui`:

```powershell
# Mock mode
flutter run

# API mode, backend on this computer (emulator or desktop)
flutter run -d emulator-5554 --dart-define=OMNIA_DATA=api

# API mode, backend somewhere else
flutter run --dart-define=OMNIA_DATA=api --dart-define=OMNIA_API_BASE_URL=http://192.168.1.20:8000/api

# From a settings file (copy omnia.env.example to omnia.env first; omnia.env is git-ignored)
flutter run --dart-define-from-file=integration/omnia.env

# A release build for a deployed backend
flutter build apk --dart-define=OMNIA_DATA=api --dart-define=OMNIA_API_BASE_URL=https://omnia.example.com/api
```

The same with the helper (it also checks `<url>/health` first in API mode):

```powershell
.\integration\run_frontend.ps1                                   # mock mode
.\integration\run_frontend.ps1 -Api -Device emulator-5554        # local backend
.\integration\run_frontend.ps1 -Api -BaseUrl http://192.168.1.20:8000/api
.\integration\run_frontend.ps1 -EnvFile integration\omnia.env
.\integration\run_frontend.ps1 -Api -DryRun                      # print the command only
```

If scripts are blocked: `powershell -ExecutionPolicy Bypass -File .\integration\run_frontend.ps1 -Api`.

## Which URL from which device

| Frontend runs on | Backend on your computer | Use |
|---|---|---|
| Android emulator | `uvicorn … --host 0.0.0.0 --port 8000` | nothing (default) or `http://10.0.2.2:8000/api` |
| Windows / web | same | nothing (default) or `http://localhost:8000/api` (web: mind CORS, above) |
| A physical phone | same, and both on one network | `http://<your computer's LAN IP>:8000/api` (debug Android only for `http`) |
| Anything | a deployed server | `https://<host>/api` |

`--host 0.0.0.0` matters for physical phones: the default `127.0.0.1` only accepts connections from the computer itself. Allow the port through the firewall if a phone can't connect.

## The reference backend

```powershell
cd ..\..\Fawaz\backend
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Swagger: `http://localhost:8000/api/docs` · health: `http://localhost:8000/api/health`.

## When it doesn't connect

| Symptom | Likely cause |
|---|---|
| "Couldn't reach OMNIA" at start-up | wrong URL, backend not running, `127.0.0.1` binding with a physical phone, firewall, `http` on a release/iOS build, or (web) the origin missing from the backend's CORS list |
| "Server not configured" | release build without `OMNIA_API_BASE_URL` |
| Sign-in works, a screen says "Couldn't load…" | that endpoint is missing or its JSON doesn't match: see [`COMPATIBILITY.md`](COMPATIBILITY.md) |
| Signed out unexpectedly | the backend answered `401` to a token the app sent |
