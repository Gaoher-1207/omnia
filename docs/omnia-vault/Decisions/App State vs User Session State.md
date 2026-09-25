---
type: decision
status: accepted
---

# App State vs User Session State

## Context

Once real accounts existed (`70864a7`), one device could be used by several accounts in sequence. Controllers created once for the app's life would carry one user's data into another user's session.

## Decision

- **Per-user state** (feature repositories and the Task, Goal and Revision controllers) lives in `UserSession`. In API mode it's keyed by `ValueKey(user.id)`, so it's disposed and rebuilt on sign-out, expiry or account switch.
- **App-wide state** (`ThemeController`, `FocusTimerController`, `ApiClient`, `AuthController`) is created once in `_OmniaAppState`.
- **Focus is intentionally app-wide** at this stage.

## Reasons

- It makes cross-user data leaks structurally impossible: a new user gets new controllers and repositories.
- Theme is a device preference. `ApiClient` and `AuthController` must outlive sessions in order to manage them.
- Focus: the countdown must survive navigation, and `FocusPhaseFeedback` has to fire on any route. It holds no user data, only a running timer and a session count.
- Mock mode keeps a single session, so behaviour there didn't change.

## Consequences

- A running focus timer continues across sign-out and sign-in. That's accepted for now.
- When focus minutes become per-user data (for example, logged to `/study/sessions`), the *logging* belongs to the session. The *timer* can stay app-wide.
- After [[Phase 3 - Tasks API Integration]], task caches are still per-session, so user B can't see user A's tasks even briefly.

Details: [[Session Architecture]] · [[Focus]] · [[Architecture Decisions]]
