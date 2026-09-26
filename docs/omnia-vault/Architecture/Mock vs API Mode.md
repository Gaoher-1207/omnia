---
type: architecture
frontend: canonical
---

# Mock vs API Mode

The canonical frontend has two data modes, chosen at build time with a `--dart-define`.

| | Mock mode (default) | API mode |
|---|---|---|
| Command | `flutter run` | `flutter run --dart-define=OMNIA_DATA=api` |
| Decided by | `ApiConfig.apiMode == false` | `String.fromEnvironment('OMNIA_DATA') == 'api'` |
| Sign-in | None | Real FastAPI accounts ([[Authentication Flow]]) |
| Backend needed | No | Yes |
| `UserSession` | One for app life | One per signed-in user ([[Session Architecture]]) |
| Tasks | In-memory mock | **FastAPI `/tasks`** via `ApiTaskRepository` (user-scoped) |
| Goals, Study | In-memory mocks | **Still in-memory mocks**, fresh per user |
| Home / Track day summary | Sample day (`MockDashboardRepository`) | **FastAPI `/dashboard`** via `ApiDashboardRepository` (user-scoped) |
| Activity and sleep logging | `MockTrackRepository`, shared with the mock dashboard so a mock log shows on Home | **FastAPI `/activity/{day}`, `/sleep/{day}`** via `ApiTrackRepository` |
| Plan, Insights, Home "Next up", Track "Today's activity" | Sample data | Sample data (labelled `SAMPLE` in API mode) |
| Focus | App-wide, local | App-wide, local |
| Settings → Account | Hidden | Shown when signed in |
| Typical use | UI work, demos, automated tests | Auth and integration work |

> [!warning] API mode is not "backend mode" yet
> Today it means *real accounts + server-backed Tasks + the server's day summary on Home and Track + local data for every other feature*. Each feature moves to the backend in its own phase. See [[Mock First API Migration]] and [[Backend Integration Roadmap]].

## Visual

```mermaid
flowchart TB
    subgraph Mock["flutter run"]
        direction TB
        m1["No AuthController"] --> m2["UserSession (single)"] --> m3["Mock repositories"]
    end
    subgraph Api["flutter run --dart-define=OMNIA_DATA=api"]
        direction TB
        a1["AuthController + ApiClient"] ==> a0[("FastAPI")]
        a1 --> a2["UserSession keyed by user.id"] --> a3["ApiTaskRepository, ApiDashboardRepository,<br/>ApiTrackRepository ⇒ FastAPI<br/>+ mock Goals / Study"]
    end
```

## Backend URL (`ApiConfig.resolveBaseUrl`)

| Situation | URL |
|---|---|
| `--dart-define=API_BASE_URL=<url>` | that URL (trailing `/` removed) |
| Debug, Android emulator | `http://10.0.2.2:8000/api` (the emulator's alias for the host) |
| Debug, web / iOS / desktop | `http://localhost:8000/api` |
| Release without `API_BASE_URL` | `null` → "Server not configured" screen |

Plain `http://` is allowed only in **debug** Android builds (`usesCleartextTraffic` in the debug manifest).

## The target state after migration

Mock mode stays permanently: tests and UI work depend on it. In API mode, each repository in `AppDependencies` is swapped for its API version as that feature's phase finishes, starting with [[Tasks]].

## Related

[[Running OMNIA]] · [[Repository Pattern]] · [[Current Status]]
