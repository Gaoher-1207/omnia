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
| Profile & daily targets (name, username, time zone, five [[Daily Targets]], preferred workout time) | `api-connected`, **API mode only** ([[Phase 5A - Profile and Daily Targets]], verified) | `ProfilePage` → `AuthController.updateProfile` → `PATCH /profile`, then `DashboardController.load()` |

Account actions go through a shared `_attempt` helper. Change password and delete account open dialogs, and destructive actions ask for confirmation first.

## Not here yet

- Data export (`GET /account/export`, [[Integrations API]]) exists in the backend but has no UI.

The profile editor sends only changed fields, shows field errors (including a taken username) on the field with a "Check the highlighted fields." message, and treats a save followed by a failed dashboard refresh as saved ("Profile saved, but Home couldn't refresh…").

## Related

[[Authentication API]] · [[Session Architecture]] · [[Preserve OMNIA Design System]]
