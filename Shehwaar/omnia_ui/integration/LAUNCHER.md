# One-click Windows development

Double-click `START_OMNIA.bat` at the repository root. Requires the existing
backend virtual environment, Flutter SDK/dependencies, Android SDK/Pixel_9 AVD,
and Ollama/model installation. Nothing is installed or downloaded by the launcher
(Flutter's normal build may still resolve its existing project dependencies).

Machine settings live in `integration/.env.launcher` (git-ignored). If absent,
`launcher.env.example` is used. Change **ASSISTANT_MODEL** in the local file to
an already installed Ollama model, then stop the backend with Ctrl+C and restart
the launcher. Only process-local environment variables are set; backend `.env`
still supplies database, authentication and other application settings. This uses
the current assistant configuration interface; it does not refactor OmniAI or
change the separate planner/photo AI provider.

The launcher validates paths, reads the Android SDK from `android/local.properties`,
starts/reuses Ollama, polls `/api/tags`, and checks the selected model exists.
It starts the backend with `.venv/Scripts/python.exe -m alembic upgrade head`,
then `-m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000`, from
`Fawaz/backend`. Migrations are the documented normal startup procedure and may
update the configured database. It waits for `/api/health/ready` and checks the
OpenAPI title, starts/reuses the configured AVD, waits for ADB, Android's
`sys.boot_completed=1` and package manager readiness, then calls the existing
`run_frontend.ps1 -Api -Device <detected serial>` in its own terminal.
Flutter uses its existing Android debug URL `http://10.0.2.2:8000/api`.

New Ollama and backend processes bind only to 127.0.0.1. An existing Ollama
server is reused without changing its binding or model directory; restart it
yourself if its configuration differs. The launcher does not start Docker or
Open WebUI, change global environment variables, or kill existing processes.

Named Windows mutexes prevent overlapping launcher runs and duplicate services
started by this launcher (within the current Windows session). Ollama is also
detected through its HTTP API. ADB's `emu avd name` identifies the exact AVD,
and process command lines detect an AVD still starting before ADB is ready.
Other emulators are left alone. An externally started backend occupying port
8000 is rejected because its assistant settings cannot be verified or changed.
Repeated launches reuse launcher-managed backend/Flutter processes; stop them
before applying changed configuration. Existing services keep their original
windows; new services receive `OMNIA - <role>` titles.

Failures are displayed in the relevant terminal and wait for Enter. Other
services remain running. Timeouts are bounded (60 seconds Ollama, 120 backend,
180 ADB discovery, 300 Android boot) and poll actual readiness every 2 seconds.

## Safe preflight

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Shehwaar\omnia_ui\integration\start_omnia.ps1 -Role Check
```

This checks paths, Flutter availability and the AVD list without starting services
or running migrations.

## Manual acceptance test

1. Run preflight. Stop any manually started backend on port 8000. Existing Ollama
   and Pixel_9 can remain running to test reuse.
2. Double-click the root BAT. Confirm named service terminals, backend readiness,
   then the app on Pixel_9. Allow the first Flutter build time to complete.
3. Open `http://127.0.0.1:8000/api/health/ready`; expect status/database `ok`.
   Sign in/register in the app and send an Ask Omnia message to exercise Ollama.
4. Edit a Flutter UI file and press `r` in the Flutter window to verify hot reload.
5. Double-click again, including during startup. Confirm no second Ollama server,
   Pixel_9 instance, backend or Flutter session is started.
6. Quit Flutter with `q`, stop backend/Ollama started by this launcher with Ctrl+C,
   and close the emulator. Double-click again to test a cold start.
7. Optionally set ASSISTANT_MODEL to a nonexistent name and retry: startup should
   report the missing model without downloading anything. Restore the setting.

Do not use administrator mode; run under the same Windows account/session as your
normal emulator. Close finished service terminals when no longer needed.
