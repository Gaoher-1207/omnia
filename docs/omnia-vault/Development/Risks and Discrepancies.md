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
| D4 | Home screen | The greeting is hard-coded as "Good morning, Shew." and ignores the signed-in user's `displayName` | Visible in API mode with any other account |
| D5 | "Goals" naming | The backend and donor call the profile's daily targets "goals". The canonical Goals feature means long-term goals. | Risk of wiring the wrong repository ([[Goals vs Daily Targets]]) |
| D6 | Study models | The canonical `StudySession` (embedded revision items) vs the backend `StudySession` (logged minutes) | Study can't be a simple repository swap ([[Study Session]]) |
| D7 | Test count | The README states 106 passing tests. The source has 101 `test`/`testWidgets` declarations, some inside loops. Not re-run. | Probably consistent, but unverified |
| D8 | Sample dates | `MockData` and screens use a fixed 23 Sep **2025** sample day, and goal deadlines fall in 2025 | Seeded goals now look overdue |

## Technical risks

| # | Risk | Detail | Suggested handling |
|---|---|---|---|
| R1 | Expiry is detected late | Only account actions make authenticated calls, so an expired 12 h token is noticed only on launch or in Settings | Phase 3 will surface it naturally. Test it explicitly. |
| R2 | No refresh tokens | JWT lifetime defaults to 720 min, and there's no refresh endpoint | Users sign in again after about 12 h. Decide whether that's acceptable. |
| R3 | Dev secret | An empty `AUTH_SECRET` in development means a random secret per process, so every restart invalidates tokens | Set it in `.env` ([[Running OMNIA]]) |
| R4 | Unawaited revision saves | `RevisionController._save` reverts and **rethrows**, but `setChecked`, `markAll` and `rename` don't await it, so a failed save becomes an unhandled async error (the state is reverted correctly) | Matters once Study is API-backed |
| R5 | In-memory rate limiter | Per-process sliding window. Multiple workers or instances each keep their own counts. | Fine for dev. Revisit for deployment. |
| R6 | Focus survives sign-out | App-wide by design | Accepted ([[App State vs User Session State]]) |
| R7 | Onboarding not persisted | `_onboardingComplete` lives in memory, so it's shown on every cold start in mock mode or when signed out | A known TODO in `app.dart` |
| R8 | Two `omnia_ui` packages | `Fawaz/lib` and `Shehwaar/omnia_ui` share the package name and several identical files | Copy only deliberately ([[Fawaz Donor Map]]) |
| R9 | Mapping edge cases (Tasks) | 00:00 local due time ⇒ sent as all-day. Sub-minute estimates are dropped. | Note in [[Phase 3 - Tasks API Integration]] |
| R10 | CI credentials | The workflow contains a hard-coded CI test-database password | Only a CI throwaway, but better moved to secrets when CI is fixed |

Related: [[Current Status]] · [[Testing]] · [[Roadmap]]
