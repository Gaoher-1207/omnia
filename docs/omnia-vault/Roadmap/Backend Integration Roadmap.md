---
type: roadmap
---

# Backend Integration Roadmap

How each canonical feature moves from local or sample data to FastAPI, following [[Mock First API Migration]]. Each phase keeps mock mode, the existing UI and the existing tests.

| # | Phase | Frontend work | Backend | Donor help | Blockers / decisions |
|---|---|---|---|---|---|
| ✅ | API infrastructure | `ApiClient`, config, errors, token store | none | adapted | none |
| ✅ | Auth + sessions | `AuthController`, `UserSession` | [[Authentication API]] | adapted | none |
| ✅ | **Tasks** | `ApiTaskRepository`, `AppDependencies.api` | [[Tasks API]] | `ApiTaskRepository` (adapted) | none. Automated and manual verification passed. See [[Phase 3 - Tasks API Integration]]. |
| ✅ | **Dashboard** (read-only) | `Dashboard`, `DashboardRepository` (mock + API), `DashboardController`. Home greeting, date, exam and cards; Track tiles. | [[Profile and Dashboard API]] | `DashboardRepository` (adapted) | none. Automated and manual verification passed. See [[Phase 4 - Dashboard API Integration]]. |
| ✅ | **5A Profile + daily targets** | `Profile` model, `AuthController.updateProfile` (changed fields only), Settings "Profile & daily targets" screen, dashboard reload after save | [[Profile and Dashboard API]] | `goals_page.dart` (as reference) | none. Automated and manual verification passed. See [[Phase 5A - Profile and Daily Targets]]. |
| ✅* | **5B Activity + sleep logging** (meals later) | `TrackRepository` (mock + API), session `TrackController`, Activity and Sleep log screens opened from the Home and Track cards; save, then reload the dashboard. Complete (automated + manual emulator verification), `0375257`. See [[Phase 5B - Activity and Sleep Logging]]. | [[Activity API]], [[Sleep API]], [[Nutrition API]] | `TrackRepository` | Design the logging screens |
| ✅ | **5C Daily plan** | `ApiPlanRepository`, `PlanController`, `DailyPlanView`, commitments and plan preferences, Today's Next up; adaptive replanning with explicit Apply. Complete: `8029231`, `a22ac4d`, `1d87602`. | [[AI API]], `/commitments` | (built in the canonical app) | Plan-block outcomes not persisted yet |
| 6 | Study | V1 done (`8601ba0`: subjects and exams). Remaining: align `StudySession`/`RevisionItem` with backlog and sessions | [[Study API]] | `ApiStudyRepository` (REFERENCE) | **Model alignment decision** ([[Study Session]]). Optionally log [[Focus]] minutes. |
| 7 | Insights / progress | Streaks, history, achievements | [[Progress API]] | `ProgressRepository` | Needs real data from phases 3–5 |
| any | Long-term Goals backend | `ApiGoalRepository` (new, for **long-term** goals) | **New module needed** (table, migration, router) | none: the donor version is incompatible | Backend design ([[Goal]]) |
| later | Social, calendar link, data export | New features | [[Social API]], [[Integrations API]] | Social is REFERENCE | Username in Settings |

## Shared plumbing, introduced by Phase 3

- `AppDependencies.api(ApiClient)`, built per session through `UserSession`'s factory. Later phases swap in more API repositories there.
- `test/support/fake_auth_backend.dart` now serves `/tasks` and `/dashboard` too; extend it per feature.
- A rule: every mapper is explicit, because the backend uses snake_case and server ids ([[Data Model Overview]]).

Related: [[Roadmap]] · [[Frontend Backend Integration]] · [[Fawaz Donor Map]]
