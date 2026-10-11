---
type: status
verified_against: main @ edf353f plus the uncommitted release-foundation work (October 11, 2026)
---

# Current Status

A snapshot verified against the source, not against the README. Back to [[00 - OMNIA|OMNIA]].

> [!summary] In one line
> **In API mode, authentication, Tasks, the profile and daily targets, the Today/Areas day summary (`/dashboard`), today's activity and sleep logs, Study subjects and exams, the daily plan (with fixed commitments, plan preferences and adaptive replanning) and the read-only Ask Omnia assistant are real (FastAPI). Goals and Focus are local; Insights, nutrition and social are not connected. No screen shows sample data in API mode.** In mock mode, nothing talks to a server and the labelled sample day is shown.
>
> Phases 3 (Tasks), 4 (Dashboard), 5A (Profile and daily targets), 5B (Activity and sleep), the UX architecture pass, Study V1, Ask Omnia, 5C (daily plan), OmniAI planning and availability, and adaptive replanning are committed on `main` (see [[Roadmap]] for commits). The release-readiness work (deterministic backend tests, a working CI workflow, these docs) is in progress; see [[Roadmap]].

## Feature integration map

```mermaid
flowchart LR
    subgraph FE["Canonical frontend (Shehwaar/omnia_ui)"]
        AUTH["Authentication ✅"]
        TASKS["Tasks ✅ API mode"]
        GOALS["Long-term Goals 🟡"]
        FOCUS["Focus ✅ local"]
        STUDY["Study ✅🟡 subjects + exams via API"]
        HOME["Today ✅ summary + Next up via API"]
        PLAN["Plan ✅ daily plan + replanning via API"]
        ASK["Ask Omnia ✅ read-only via API"]
        TRACK["Areas ✅🟡 tiles + logging via API"]
        INS["Insights ⚪ empty"]
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
        P1["/ai/daily-plan · /ai/replan/* · /commitments"]
        C1["/ai/chat"]
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
    HOME -->|mock mode only: sample Next up| SD
    PLAN -->|mock mode only| SD
    PLAN ==>|API mode| P1
    HOME ==>|API mode: Next up| P1
    ASK ==>|API mode| C1
    TRACK -->|mock mode| MD
    TRACK ==>|API mode, same controller| D1
    HOME -.->|live count| TASKS
    HOME -.->|preview| GOALS
    TRACK -.->|live tile| TASKS
    PLAN -.->|entry| FOCUS

    STUDY ==>|API mode: subjects, exams| S1
    TRACK ==>|API mode: activity, sleep| TR
    INS -.-|exists, not connected| PR
```

Thick arrow = wired today. Dotted arrows to the backend = the backend endpoint exists, but the canonical frontend doesn't call it.

## Status table

| Area | Status | Data source today | Backend support | Note |
|---|---|---|---|---|
| [[Authentication Flow\|Authentication]] | `api-connected` | FastAPI `/auth/*` | [[Authentication API]] | Manually verified on the Android emulator (per README) |
| [[Tasks]] | `api-connected` (API mode) | `ApiTaskRepository` (API mode) · `MockTaskRepository` (mock mode) | [[Tasks API]] full CRUD | [[Phase 3 - Tasks API Integration]]: complete (automated + manual emulator verification) |
| [[Goals]] (long-term) | `api-connected` (API mode) | `ApiGoalRepository` (`/api/goals`, migration `0009`) · `MockGoalRepository` in mock mode (labelled "not saved") | `/goals` | Not the same as [[Daily Targets]] |
| [[Focus]] | `api-connected` (study time) | `FocusTimerController` (app-wide); each finished Focus phase is saved as study minutes by the signed-in session (`POST /study/sessions`) | `/study/sessions` | The timer itself is not stored |
| [[Study]] | `partial` | API mode: subjects and upcoming exams via `/study/subjects`, `/study/exams` (Study V1, `8601ba0`); study minutes and next exam from `/dashboard`. Sample data and the revision session in mock mode only | [[Study API]] | Backlog, sessions and the study plan endpoint not wired |
| [[Dashboard]] (Today) | `partial` | API mode: greeting, name, date, next exam and Study/Activity/Sleep from `/dashboard`. Mock mode: `MockDashboardRepository` (the sample day). Tasks card and Goals preview unchanged. API mode: Next up comes from today's daily plan ("No plan yet." with an Open Plan action when none exists); mock mode keeps the labelled sample. | [[Profile and Dashboard API]] | [[Phase 4 - Dashboard API Integration]]: complete (automated + manual emulator verification) |
| [[Plan]] | `api-connected` (API mode) · `sample` (mock) | API: `ApiPlanRepository` (`GET`/`POST /ai/daily-plan`), fixed commitments and availability (`/commitments`), plan preferences (`/profile`), "Why?" explanation, and "Adjust today's plan" (`/ai/replan/proposals`, explicit Apply/Cancel). Mock: `samplePlan` constant | [[AI API]] | 5C complete (`8029231`, `a22ac4d`); adaptive replanning `1d87602`. Plan-block outcomes (done/partly/skipped) are saved and used by replanning (uncommitted, migration `0008`) |
| [[Areas]] (was Track) | `partial` | Study/Tasks/Goals/Activity/Sleep tiles from the session controllers; each opens its area ([[Phase 5B - Activity and Sleep Logging]] for the logs) | `/dashboard`; [[Activity API]], [[Sleep API]] | No meals logging |
| [[Insights]] | `partial` | Week and month workout and step insights with habit grids from `GET /activity?from&to`; only logged days count (uncommitted) | [[Activity API]] | Sleep, study, tasks and progress/streak views not built |
| [[Settings]] | `api-connected` (account section) | Theme local; account and profile via `AuthController` | [[Authentication API]], [[Profile and Dashboard API]] | Account section and "Profile & daily targets" only in API mode |
| [[Daily Targets]] | `api-connected` (API mode) | Edited in Settings → "Profile & daily targets" (`PATCH /profile`); shown as the card and tile targets from `/dashboard` | `/profile`, `/dashboard` | [[Phase 5A - Profile and Daily Targets]]: complete (automated + manual emulator verification) |
| [[Nutrition]] | `planned` | None | [[Nutrition API]] | Backend exists; no frontend yet |
| Social | `planned` | None | [[Social API]] | Backend exists; no frontend yet |
| [[AI Assistant]] | `api-connected` (read-only) | Ask Omnia: `ApiAssistantRepository` (`POST /ai/chat`), context-aware answers; a change request offers "Preview plan change" (the validated replan preview) | [[AI API]] | Never changes data itself; only the user's Apply does |
| [[Achievements and Life Timeline]] | `planned` | None | `/achievements` (fixed list) | Life Timeline is vision only |

## Mode matrix

See [[Mock vs API Mode]].

| | Mock mode (`flutter run`) | API mode (`--dart-define=OMNIA_DATA=api`) |
|---|---|---|
| Sign-in | None | Real (FastAPI) |
| Tasks | In-memory, one session for app life | **FastAPI `/tasks`**, scoped to the signed-in user |
| Goals | In-memory sample goals, one session for app life | **FastAPI `/goals`**, per user |
| Study | Sample subject, exam and revision session (labelled) | **FastAPI `/study/subjects`, `/study/exams`**, per user; revision session hidden |
| Focus | App-wide, local | App-wide timer; finished Focus phases saved as study time |
| Today / Areas day summary | Sample (`MockDashboardRepository`, steps and sleep from the shared mock track state) | **FastAPI `/dashboard`**, per user |
| Today's activity and sleep logs | In-memory `MockTrackRepository` (seeded with the sample day) | **FastAPI `/activity/{day}`, `/sleep/{day}`**, per user |
| Plan | Sample (labelled) | **FastAPI `/ai/daily-plan`**, `/commitments`, `/ai/replan/*`, per user |
| Ask Omnia | Canned local answers | **FastAPI `/ai/chat`** (read-only) |
| Insights | In-memory sample activity (labelled) | **FastAPI `/activity` range**, logged days only |

## What "verified" means here

- Wiring was read from `lib/app.dart`, `lib/core/session.dart` and `lib/core/app_dependencies.dart`: `AppDependencies.mock()` is used in mock mode and `AppDependencies.api(api)` for signed-in sessions in API mode (Tasks and the dashboard).
- Sample content is gated by `AppDependencies.sampleContent` (true only in mock mode); screens were checked for their on-screen labels (`SAMPLE DAY`, `SAMPLE DATA`) and the `samplePlan` constant.
- The emulator check of authentication is recorded in `Shehwaar/README.md`. It was not re-run while building this vault.
