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
| `tasks_test.dart` | controller CRUD, busy guard, failures, form, delete confirm, error state, live Home count | 8 |
| `ui_hardening_test.dart` | semantics, large text on small screens | 8 |
| `widget_test.dart` | app smoke, dark-mode contrast ≥ 4.5 | 5 |
| `data_foundation_test.dart` | JSON round-trips, in-memory CRUD, revision saves | 4 |
| `onboarding_test.dart` | onboarding flow, reduced motion | 3 |

That's **101 declarations** in source. Some sit inside loops (for example per brightness or per platform), so the runtime count is higher. `Shehwaar/README.md` records **106 passing** at the auth checkpoint. The suite **wasn't re-run** while building this vault.

Test doubles: `test/support/fake_auth_backend.dart` (a fake FastAPI for `/auth/*` with the real JSON and status codes) and `http`'s `MockClient`. No test needs a running server.

## Backend (`Fawaz/backend/tests`)

```bash
cd Fawaz/backend && ruff check . && pytest
```

96 `def test_` functions across 12 files: auth 12, tasks 6, study 10, planner 10, AI 16, activity/progress 10, phase2 (sleep and meals) 15, social 11, phase4 (calendar and export) 5, dashboard 3, errors/health 7, migrations 1. It runs on in-memory SQLite by default, or on PostgreSQL with `TEST_DATABASE_URL`. There's also `scripts/integration_check.py` for end-to-end checks across a restart.

## CI

⚠️ The repository's only workflow (`.github/workflows/backend-ci.yml`) doesn't actually test this backend or the Flutter app. See [[Risks and Discrepancies]].

## For Phase 3

Add fake-backend routes for `/tasks` and API-repository mapping tests, and keep every mock-mode test unchanged. See [[Phase 3 - Tasks API Integration]].

Related: [[Running OMNIA]] · [[Git Checkpoints]]
