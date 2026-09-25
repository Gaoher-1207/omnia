---
type: architecture
---

# Frontend Backend Integration

The central mapping note: for each canonical feature, it traces **controller → repository interface → current implementation → Fawaz donor → backend module**. Every row was checked against source. "—" means the relationship doesn't exist; it has not been left out for convenience.

Legend: **CURRENT** = what runs today · **DONOR** = exists in `Fawaz/lib` · **BACKEND** = exists in `Fawaz/backend`.

## Map

| Canonical feature | Controller (canonical) | Repository interface | CURRENT implementation | DONOR implementation | BACKEND | Connected? |
|---|---|---|---|---|---|---|
| [[Authentication Flow\|Auth]] | `AuthController` | — (uses `ApiClient`) | `ApiClient` → FastAPI | `core/auth/auth_controller.dart` (already adapted) | [[Authentication API]] | ✅ API mode |
| [[Tasks]] | `TaskController` | `TaskRepository` | `ApiTaskRepository` (API mode) · `MockTaskRepository` (mock mode) | `ApiTaskRepository` (adapted) | [[Tasks API]] | ✅ API mode (Phase 3, verified) |
| [[Goals]] (long-term) | `GoalController` | `GoalRepository` | `MockGoalRepository` | ⚠️ `ApiGoalRepository` is **[[Daily Targets]]**, not long-term goals | — none | ❌ needs new module |
| [[Daily Targets]] | — | — | — | `ApiGoalRepository` + `settings/goals_page.dart` | [[Profile and Dashboard API]] (`/profile`, `/dashboard`) | ❌ not in canonical |
| [[Study]] (revision session) | `RevisionController` | `StudyRepository` (5 methods, session-centred) | `MockStudyRepository` | `ApiStudyRepository` — **different, larger interface** (subjects, exams, topics, sessions, plan) | [[Study API]] | ❌ model alignment needed |
| [[Focus]] | `FocusTimerController` | — | local | `plan/focus_session_page.dart` (stopwatch that logs a study session) | `POST /study/sessions` (logging only) | ❌ optional |
| [[Dashboard]] (Home) | none (reads `TaskScope`, `GoalScope`, `RevisionScope`) | — | sample + live counts | `home/data/dashboard_repository.dart` | `GET /dashboard` | ❌ |
| [[Plan]] | none (`samplePlan` const) | — | sample | `plan/data/plan_repository.dart`, `PlanController` | [[AI API]] `/ai/daily-plan` | ❌ |
| [[Track]] | none (reads `TaskScope`) | — | sample + live Tasks tile | `track/data/track_repository.dart` | [[Activity API]], [[Sleep API]], [[Nutrition API]] | ❌ |
| [[Insights]] | none | — | sample | `insights/data/progress_repository.dart` | [[Progress API]] | ❌ |
| [[Settings]] | `ThemeController`, `AuthController` | — | theme local; account → FastAPI | `settings/settings_page.dart` | [[Authentication API]] | ✅ account section |
| Social | — (no feature) | — | — | `social/data/social_repository.dart` + pages | [[Social API]] | ❌ |
| Calendar feed / data export | — | — | — | — (not called by donor repos) | [[Integrations API]] | ❌ |

## The Tasks path (Phase 3)

```mermaid
flowchart LR
    UI["TasksPage · TaskFormPage<br/>Home card · Track tile"] --> TC["TaskController"]
    TC --> TR["TaskRepository"]
    TR -->|mock mode| MT["MockTaskRepository"]
    TR ==>|API mode| AT["ApiTaskRepository<br/>(adapted from donor)"]
    AT ==> AC["ApiClient"]
    AC ==> BE["/api/tasks<br/>Fawaz/backend/app/modules/tasks"]
    BE ==> DB[("tasks table")]
```

Details: [[Phase 3 - Tasks API Integration]].

## Why some rows can't simply be "switched on"

- **Goals:** the backend has no long-term goals. The donor's `ApiGoalRepository` presents the five profile targets (study, tasks, steps, sleep, kcal) as "goals" read from `/dashboard` and written with `PATCH /profile`. Wiring it into the canonical `GoalRepository` would silently swap the concept. See [[Goals vs Daily Targets]].
- **Study:** the canonical `StudySession` embeds a list of `RevisionItem`s. The backend's `StudySession` is a *logged block of time* (minutes, date, optional backlog item), and revision topics are separate `BacklogItem`s with `kind = revision`. See [[Study Session]].
- **Plan and Dashboard:** the canonical screens have no controllers or domain models for this data yet. That work is new UI wiring inside the existing design, not a repository swap.

## Related

[[Architecture Overview]] · [[Fawaz Donor Map]] · [[API Map]] · [[Backend Integration Roadmap]] · [[Data Model Overview]]
