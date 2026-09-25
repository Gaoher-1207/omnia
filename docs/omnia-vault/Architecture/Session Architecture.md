---
type: architecture
frontend: canonical
---

# Session Architecture

How the canonical frontend separates **app-wide** state from **per-user** state. The decision behind it is recorded in [[App State vs User Session State]].

**Code:** `lib/core/session.dart` (`UserSession`), `lib/app.dart` (`_OmniaAppState`).

## The two layers

```mermaid
flowchart TD
    subgraph AppWide["App-wide: created once in _OmniaAppState"]
        TH["ThemeController"]
        FT["FocusTimerController<br/>(intentionally app-wide)"]
        API["ApiClient (API mode)"]
        AUTH["AuthController (API mode)"]
    end
    subgraph Session["UserSession: one per signed-in user"]
        DEPS["AppDependencies<br/>(tasks, goals, study repositories)"]
        TC["TaskController"]
        GC["GoalController"]
        RC["RevisionController"]
    end
    AppWide --> Session
    Session --> MA["MaterialApp → OmniaHome"]
```

| App-wide | Per user (`UserSession`) |
|---|---|
| `ThemeController` | `AppDependencies` |
| `FocusTimerController` | `TaskController` (`..load()` on creation) |
| `ApiClient` | `GoalController` (`..load()` on creation) |
| `AuthController` | `RevisionController` |

## Lifecycle

- **Mock mode:** one `UserSession` for the life of the app.
- **API mode:** `UserSession(key: ValueKey(user.id))`. Sign-out, session expiry or switching accounts removes the widget, and `dispose()` tears down its controllers. The next user gets a new `AppDependencies.mock()`, which means **fresh in-memory data**.

This guarantees that one user's local data can't carry over into another user's session. Today that data is only mock data. After [[Phase 3 - Tasks API Integration]], the same boundary will make sure user B never sees user A's cached tasks.

## Why Focus is not per user

The Focus timer is deliberately app-wide: a running countdown shouldn't reset when a screen changes, and `FocusPhaseFeedback` (wrapped around every route in `MaterialApp.builder`) has to feel the phase end on any screen. A side effect is that a running timer **survives sign-out and a change of user**. At the current stage that's accepted. See [[Focus]].

## Placement detail

`UserSession` wraps `MaterialApp` (`_session(home) → UserSession(child: _app(home))`), so every pushed route (Tasks, Goals, Revision, Focus) can reach the session scopes.

## Related

[[Authentication Flow]] · [[Repository Pattern]] · [[Mock vs API Mode]] · [[Flutter Architecture]]
