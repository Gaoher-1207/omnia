---
type: feature
status: api-connected
frontend: canonical
backend_available: true
backend_connected: true
---

# Settings

Opened from the Home app bar. **Code:** `features/settings/settings_page.dart`.

## Current Status

| Section | Status | Source |
|---|---|---|
| Light / dark theme switch | `implemented` (local, not persisted) | `ThemeController` (app-wide) |
| Preview onboarding | `implemented`, **debug builds only** | pushes `OnboardingPage` |
| Account (email/name, change password, sign out, sign out everywhere, delete account) | `api-connected`, **API mode and signed in only** | `AuthScope.maybeOf(context)?.user` → [[Authentication Flow]] |

Account actions go through a shared `_attempt` helper. Change password and delete account open dialogs, and destructive actions ask for confirmation first.

## Not here yet

- **Daily targets editor** (study minutes, steps, tasks, sleep, kcal → `PATCH /profile`). It's planned for the dashboard phase. See [[Daily Targets]] and [[Backend Integration Roadmap]].
- Username (needed for social features), timezone editing and data export (`GET /account/export`, [[Integrations API]]) exist in the backend but have no UI.

## Related

[[Authentication API]] · [[Session Architecture]] · [[Preserve OMNIA Design System]]
