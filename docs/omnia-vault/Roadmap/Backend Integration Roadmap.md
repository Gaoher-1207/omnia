---
type: roadmap
---

# Backend Integration Roadmap

How each canonical feature moves from local or sample data to FastAPI, following [[Mock First API Migration]]. Each phase keeps mock mode, the existing UI and the existing tests.

| # | Phase | Frontend work | Backend | Donor help | Blockers / decisions |
|---|---|---|---|---|---|
| ✅ | API infrastructure | `ApiClient`, config, errors, token store | none | adapted | none |
| ✅ | Auth + sessions | `AuthController`, `UserSession` | [[Authentication API]] | adapted | none |
| **3** | **Tasks** | `ApiTaskRepository`, API-aware `AppDependencies` | [[Tasks API]] | `ApiTaskRepository` (REUSE / ADAPT) | none. See [[Phase 3 - Tasks API Integration]]. |
| 4 | Dashboard + daily targets | Dashboard model and repository. Home and Track cards. Settings targets editor. Greeting from `display_name`. | [[Profile and Dashboard API]] | `DashboardRepository`, `goals_page.dart` (as reference) | Keep separate from long-term Goals ([[Goals vs Daily Targets]]) |
| 5 | Daily plan | Plan model, repository and controller. Timeline and list fed by the API. Regenerate with a note. | [[AI API]] | `PlanRepository`, `PlanController` | How the revision item and Focus entry attach to API plan items |
| 6 | Study | Align `StudySession`/`RevisionItem` with subjects, exams, backlog and sessions | [[Study API]] | `ApiStudyRepository` (REFERENCE) | **Model alignment decision** ([[Study Session]]). Optionally log [[Focus]] minutes. |
| 7 | Activity / sleep (/ meals) | Logging UI in the Track design | [[Activity API]], [[Sleep API]], [[Nutrition API]] | `TrackRepository` | Design the logging screens |
| 8 | Insights / progress | Streaks, history, achievements | [[Progress API]] | `ProgressRepository` | Needs real data from phases 3–7 |
| any | Long-term Goals backend | `ApiGoalRepository` (new, for **long-term** goals) | **New module needed** (table, migration, router) | none: the donor version is incompatible | Backend design ([[Goal]]) |
| later | Social, calendar link, data export | New features | [[Social API]], [[Integrations API]] | Social is REFERENCE | Username in Settings |

## Shared plumbing, introduced by Phase 3

- A way to build per-session `AppDependencies` from the app-wide `ApiClient` in API mode.
- A fake-backend extension for feature endpoints in tests. The donor's `test/support/fake_backend.dart` is a starting point.
- A rule: every mapper is explicit, because the backend uses snake_case and server ids ([[Data Model Overview]]).

Related: [[Roadmap]] · [[Frontend Backend Integration]] · [[Fawaz Donor Map]]
