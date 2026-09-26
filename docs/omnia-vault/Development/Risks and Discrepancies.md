---
type: development
recorded: 2026-09-25
---

# Risks and Discrepancies

Found while building this vault by comparing the READMEs, the canonical frontend and the backend. **Nothing here was changed in code.** It's a list to decide on.

## Discrepancies

| # | Where | What | Impact |
|---|---|---|---|
| D1 | `.github/workflows/backend-ci.yml` | The only workflow installs from **`Fawz/backend`** (typo for `Fawaz`) and runs a **Django** `manage.py check \|\| true`. The backend is FastAPI. Nothing runs pytest or Flutter tests. | CI passes without testing anything |
| D2 | `Fawaz/README.md` | Describes `.github/workflows/ci.yml` (backend on SQLite and PostgreSQL, migrations, `flutter analyze`/`test`). **That file doesn't exist** in the repository. | Misleading assurance |
| D3 | `Fawaz/README.md` | Calls its `lib/` "the product UI" / "Shew's UI". It's the older donor, not the canonical frontend. | Confusion over what the app is ([[Canonical Frontend]]) |
| D4 | Home screen | ~~The greeting is hard-coded as "Good morning, Shew."~~ Resolved in API mode by [[Phase 4 - Dashboard API Integration]] (server `greeting` + `display_name`). Mock mode still shows the sample "Shew". | None in API mode |
| D5 | "Goals" naming | The backend and donor call the profile's daily targets "goals". The canonical Goals feature means long-term goals. | Risk of wiring the wrong repository ([[Goals vs Daily Targets]]) |
| D6 | Study models | The canonical `StudySession` (embedded revision items) vs the backend `StudySession` (logged minutes) | Study can't be a simple repository swap ([[Study Session]]) |
| D7 | Test count | Re-run: 106 passing at the auth checkpoint; 128 after Phase 3; 146 after Phase 4; 164 after Phase 5A; 192 after Phase 5B. The README still says 106 (a checkpoint). | Update at the next documentation checkpoint |
| D9 | `Fawaz/backend/tests/test_dashboard.py`, `test_phase2.py`, `test_activity_progress.py` | `test_dashboard_reflects_today`, three sleep tests in `test_phase2.py` and three activity tests use the machine's local `date.today()` while the dashboard uses the profile time zone (UTC in tests), so it fails when those dates differ (e.g. just after local midnight east of UTC) | A flaky backend test, not an app bug. They all pass with `TZ=UTC0`. Not changed (backend out of scope). |
| D8 | Sample dates | `MockData` and screens use a fixed 23 Sep **2025** sample day, and goal deadlines fall in 2025 | Seeded goals now look overdue |

## Technical risks

| # | Risk | Detail | Suggested handling |
|---|---|---|---|
| R1 | Expiry detection | Since Phase 3, task calls are routine authenticated calls, so expiry surfaces during normal use in API mode. Tested with a fake backend and a live backend. | Resolved for Tasks |
| R2 | No refresh tokens | JWT lifetime defaults to 720 min, and there's no refresh endpoint | Users sign in again after about 12 h. Decide whether that's acceptable. |
| R3 | Dev secret | An empty `AUTH_SECRET` in development means a random secret per process, so every restart invalidates tokens | Set it in `.env` ([[Running OMNIA]]) |
| R4 | Unawaited revision saves | `RevisionController._save` reverts and **rethrows**, but `setChecked`, `markAll` and `rename` don't await it, so a failed save becomes an unhandled async error (the state is reverted correctly) | Matters once Study is API-backed |
| R5 | In-memory rate limiter | Per-process sliding window. Multiple workers or instances each keep their own counts. | Fine for dev. Revisit for deployment. |
| R6 | Focus survives sign-out | App-wide by design | Accepted ([[App State vs User Session State]]) |
| R7 | Onboarding not persisted | `_onboardingComplete` lives in memory, so it's shown on every cold start in mock mode or when signed out | A known TODO in `app.dart` |
| R8 | Two `omnia_ui` packages | `Fawaz/lib` and `Shehwaar/omnia_ui` share the package name and several identical files | Copy only deliberately ([[Fawaz Donor Map]]) |
| R9 | Mapping edge cases (Tasks) | 00:00 local due time ⇒ sent as all-day. Sub-minute estimates are dropped. Due dates are device-local calendar days, while the backend's "today" uses the profile time zone. | Accepted in Phase 3 (a `ponytail:` comment in `api_task_repository.dart`) |
| R11 | Dashboard targets of 0 | A daily target of 0 ("not tracking") shows as `/ 0m` with an empty bar. Since 5A users can set 0 from the editor (its helper says "0 turns it off"). | Still open: decide how Home should show an untracked target |
| R10 | CI credentials | The workflow contains a hard-coded CI test-database password | Only a CI throwaway, but better moved to secrets when CI is fixed |

Related: [[Current Status]] · [[Testing]] · [[Roadmap]]
