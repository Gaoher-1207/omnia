---
type: status
verified_against: Phase 4 checkpoint (Dashboard API), after e141846
---

# Current Status

A snapshot verified against the source, not against the README. Back to [[00 - OMNIA|OMNIA]].

> [!summary] In one line
> **In API mode, authentication, Tasks and the Home/Track day summary (`/dashboard`) are real (FastAPI); every other feature's data is still local.** In mock mode, nothing talks to a server.
>
> Phase 3 (Tasks) is complete and manually verified. Phase 4 (Dashboard, read-only) is complete: automated verification passed and it was manually verified on the Android emulator against the real backend.

## Feature integration map

```mermaid
flowchart LR
    subgraph FE["Canonical frontend (Shehwaar/omnia_ui)"]
        AUTH["Authentication ✅"]
        TASKS["Tasks ✅ API mode"]
        GOALS["Long-term Goals 🟡"]
        FOCUS["Focus ✅ local"]
        STUDY["Study revision 🟡"]
        HOME["Home ✅🟡 summary via API"]
        PLAN["Plan ⚪"]
        TRACK["Track ✅🟡 tiles via API"]
        INS["Insights ⚪"]
    end
    subgraph Local["In-memory (lost on restart)"]
        MT[(MockTaskRepository)]
        MG[(MockGoalRepository)]
        MS[(MockStudyRepository)]
        MD[(MockDashboardRepository)]
        SD[["Hard-coded sample data"]]
    end
    subgraph BE["FastAPI (Fawaz/backend)"]
        A1["/auth/*"]
        T1["/tasks"]
        S1["/study/*"]
        D1["/dashboard"]
        PF["/profile"]
        P1["/ai/daily-plan"]
        TR["/activity · /sleep · /meals"]
        PR["/progress · /achievements"]
    end

    AUTH ==> A1
    TASKS -->|mock mode| MT
    TASKS ==>|API mode| T1
    GOALS --> MG
    STUDY --> MS
    HOME -->|mock mode| MD
    HOME ==>|API mode| D1
    HOME -->|Next up, Why?| SD
    PLAN --> SD
    TRACK -->|mock mode| MD
    TRACK ==>|API mode, same controller| D1
    TRACK -->|Today's activity| SD
    INS --> SD
    HOME -.->|live count| TASKS
    HOME -.->|preview| GOALS
    TRACK -.->|live tile| TASKS
    PLAN -.->|entry| FOCUS

    STUDY -.-|exists, models differ| S1
    PLAN -.-|exists, not connected| P1
    TRACK -.-|exists, not connected| TR
    INS -.-|exists, not connected| PR
```

Thick arrow = wired today. Dotted arrows to the backend = the backend endpoint exists, but the canonical frontend doesn't call it.

## Status table

| Area | Status | Data source today | Backend support | Note |
|---|---|---|---|---|
| [[Authentication Flow\|Authentication]] | `api-connected` | FastAPI `/auth/*` | [[Authentication API]] | Manually verified on the Android emulator (per README) |
| [[Tasks]] | `api-connected` (API mode) | `ApiTaskRepository` (API mode) · `MockTaskRepository` (mock mode) | [[Tasks API]] full CRUD | [[Phase 3 - Tasks API Integration]]: complete (automated + manual emulator verification) |
| [[Goals]] (long-term) | `local-functional` | `MockGoalRepository` | ❌ none | Not the same as [[Daily Targets]] |
| [[Focus]] | `local-functional` | `FocusTimerController` (app-wide, not stored) | `/study/sessions` could log time | Intentionally app-wide |
| [[Study]] (revision session) | `partial` | `MockStudyRepository`, one sample session | [[Study API]] | Frontend and backend models differ |
| [[Dashboard]] (Home) | `partial` | API mode: greeting, name, date, next exam and Study/Activity/Sleep from `/dashboard`. Mock mode: `MockDashboardRepository` (the sample day). Tasks card and Goals preview unchanged. Next up and "Why?" still sample (labelled in API mode). | [[Profile and Dashboard API]] | [[Phase 4 - Dashboard API Integration]]: complete (automated + manual emulator verification) |
| [[Plan]] | `sample` | `samplePlan` constant | [[AI API]] | Revision item and Focus entry are live |
| [[Track]] | `partial` | Study/Activity/Sleep tiles from the same dashboard as Home (API mode); live Tasks tile; "Today's activity" still sample (labelled in API mode) | `/dashboard`; [[Activity API]], [[Sleep API]], [[Nutrition API]] for logging | No logging UI yet |
| [[Insights]] | `sample` | Hard-coded | [[Progress API]] | |
| [[Settings]] | `api-connected` (account section) | Theme local; account via `AuthController` | [[Authentication API]] | Account section only in API mode |
| [[Daily Targets]] | `partial` (read-only) | Shown as the card and tile targets, read from `/dashboard` (API mode) | `/profile` | No editor yet: the next phase |
| [[Nutrition]] | `planned` | None | [[Nutrition API]] | Donor UI exists |
| Social | `planned` | None | [[Social API]] | Donor UI exists |
| [[AI Assistant]] | `planned` | None | [[AI API]] (daily plan only) | No AI in canonical frontend |
| [[Achievements and Life Timeline]] | `planned` | None | `/achievements` (fixed list) | Life Timeline is vision only |

## Mode matrix

See [[Mock vs API Mode]].

| | Mock mode (`flutter run`) | API mode (`--dart-define=OMNIA_DATA=api`) |
|---|---|---|
| Sign-in | None | Real (FastAPI) |
| Tasks | In-memory, one session for app life | **FastAPI `/tasks`**, scoped to the signed-in user |
| Goals / Study | In-memory, one session for app life | In-memory, **fresh per signed-in user** |
| Focus | App-wide, local | App-wide, local |
| Home / Track day summary | Sample (`MockDashboardRepository`) | **FastAPI `/dashboard`**, per user |
| Everything else | Sample | Sample |

## What "verified" means here

- Wiring was read from `lib/app.dart`, `lib/core/session.dart` and `lib/core/app_dependencies.dart`: `AppDependencies.mock()` is used in mock mode and `AppDependencies.api(api)` for signed-in sessions in API mode (Tasks and the dashboard).
- Sample screens were identified by their on-screen labels (`SAMPLE DAY`, `SAMPLE DATA`) and the `samplePlan` constant.
- The emulator check of authentication is recorded in `Shehwaar/README.md`. It was not re-run while building this vault.
