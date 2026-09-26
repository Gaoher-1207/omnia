---
type: development
---

# Testing

## Canonical frontend (`Shehwaar/omnia_ui/test`)

```powershell
flutter analyze
flutter test
```

| File | Area | `test`/`testWidgets` declarations |
|---|---|---|
| `api_client_test.dart` | `ApiConfig` URLs, bearer token, JSON, error envelope, network and timeouts, expiry signal, `TokenStore` | 24 |
| `auth_test.dart` | mock bypass, restore, offline retry, sign-in and registration validation, sign-out(-everywhere), change password, delete account, expiry, per-user sessions, auth layout at large text in both themes | 15 |
| `goals_test.dart` | percentages, decimals, above target, explicit completion, completion-only, legacy JSON, sorting, Home preview | 19 |
| `focus_timer_test.dart` | presets, validation, controls, deadline countdown, counting, survives navigation, one-shot feedback | 15 |
| `dashboard_api_test.dart` | `DashboardOut`↔`Dashboard` mapping (nullable sleep and exam), `ApiDashboardRepository` scoping/401/503/offline, mock sample day, controller load/fail/retry (keeps last day), repository selection, Home and Track in both modes, no-exam state, retry, pull-to-refresh, app-resume refresh, user switch, expiry during refresh, 200% text | 18 |
| `track_logging_test.dart` | activity and sleep mapping (not logged vs 0), `ApiTrackRepository` whole-day PUTs, delete, user scoping, 401/422 (future date, range)/503/offline, `TrackController` (reload only after a stored change, refused change, saved-not-refreshed, already-deleted, busy guard), shared mock state, Home and Track card navigation, pre-fill, workout and bedtime/wake time preserved, turning the workout off, empty sleep, remove with confirmation, server day, no log before today loads, validation, offline keeps input, refresh failure, expiry, user isolation, mock mode, 200% text in light and dark | 27 |
| `profile_test.dart` | `ProfileOut`↔`Profile`, changed-fields-only diff, `AuthController.updateProfile` (PATCH body, merge, 409, 422), a load asked for mid-flight reloads, mock mode has no editor, new target/name/time zone shown on Home without restart, taken username on its field, client validation, no-change save, save + failed refresh, offline, expiry during save, user isolation, 200% text | 18 |
| `tasks_api_test.dart` | Task↔JSON mapping, `ApiTaskRepository` list/paging/create/update/clear/complete/reopen/delete, user scoping, errors, controller on the API, repository selection per mode, Tasks screen end-to-end in API mode, restart persistence, retry, expiry during a task change | 22 |
| `tasks_test.dart` | controller CRUD, busy guard, failures, form, delete confirm, error state, live Home count | 8 |
| `ui_hardening_test.dart` | semantics, large text on small screens | 8 |
| `widget_test.dart` | app smoke, dark-mode contrast ≥ 4.5 | 5 |
| `data_foundation_test.dart` | JSON round-trips, in-memory CRUD, revision saves | 4 |
| `onboarding_test.dart` | onboarding flow, reduced motion | 3 |

Some tests sit inside loops (for example per brightness or per platform), so the runtime count is higher than the declarations: **220 passing** after the UX architecture pass and typography (`test/ux_architecture_test.dart` covers the tabs, per-tab stacks, empty states in API mode, selectors and typography), 196 at the Phase 5B commit, 164 after Phase 5A, 146 after Phase 4, 128 after Phase 3, 106 at the auth checkpoint.

Test doubles: `test/support/fake_auth_backend.dart` (a fake FastAPI for `/auth/*`, `/profile`, `/tasks`, `/dashboard`, `/activity/{day}` and `/sleep/{day}` with the real JSON, status codes, validation and user scoping) and `http`'s `MockClient`. No test needs a running server.

## Backend (`Fawaz/backend/tests`)

```bash
cd Fawaz/backend && ruff check . && pytest
```

96 `def test_` functions across 12 files: auth 12, tasks 6, study 10, planner 10, AI 16, activity/progress 10, phase2 (sleep and meals) 15, social 11, phase4 (calendar and export) 5, dashboard 3, errors/health 7, migrations 1. It runs on in-memory SQLite by default, or on PostgreSQL with `TEST_DATABASE_URL`. There's also `scripts/integration_check.py` for end-to-end checks across a restart.

`test_dashboard.py::test_dashboard_reflects_today` depends on the machine clock: it logs activity for the machine's local `date.today()`, while `/dashboard` uses the profile time zone (UTC in the tests). It fails whenever the local and UTC dates differ (seen during Phase 4 at 01:45 UTC+5). Three `test_phase2.py` tests (`test_sleep_upsert_range_and_privacy`, `test_dashboard_and_progress_include_sleep_and_calories`, `test_ai_context_includes_sleep_but_no_identity`) fail the same way (seen during Phase 5A at 02:23 local / 20:53 UTC), and so do `test_activity_progress.py`'s `test_activity_upsert_is_idempotent`, `test_activity_clears_workout_details_when_not_done` and `test_activity_range_fills_missing_days` (Phase 5B, 02:55 local). With the local clock on UTC (`TZ=UTC0 pytest ...`) all of `test_activity_progress.py`, `test_phase2.py`, `test_dashboard.py` and `test_auth.py` pass (40 tests). See D9 in [[Risks and Discrepancies]].

## CI

⚠️ The repository's only workflow (`.github/workflows/backend-ci.yml`) doesn't actually test this backend or the Flutter app. See [[Risks and Discrepancies]].

## Phase 3

Added `/tasks` fake-backend routes and `tasks_api_test.dart`; every mock-mode test is unchanged. Two `auth_test.dart` expectations were updated because API-mode sessions now load `/tasks` after `/auth/me`. A one-off live check against a throwaway FastAPI instance (separate SQLite database) was also run and then removed. See [[Phase 3 - Tasks API Integration]].

Related: [[Running OMNIA]] · [[Git Checkpoints]]
