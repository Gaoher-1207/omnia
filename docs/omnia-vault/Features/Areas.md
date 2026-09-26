---
type: feature
status: partial
frontend: canonical
backend_available: true
backend_connected: partial
donor: false
---

# Areas

The **Areas** tab (it replaced Track): the parts of life OMNIA manages, each opening its own screen. "Areas" is a working label. See [[Navigation and Information Architecture]].

## Current Status

`partial`. Five tiles, each showing only what its controller really knows:

| Tile | Status shown | Source | Opens |
|---|---|---|---|
| Study | study minutes / daily target | `DashboardController` | Study screen (under the tab bar) |
| Tasks | `done of total` | `TaskController` | [[Tasks]] |
| Goals | `N active`, `N completed` | `GoalController` (local-only) | [[Goals]] |
| Activity | steps / daily target | `DashboardController` | today's activity log (full screen) |
| Sleep | sleep or **Not logged** / target | `DashboardController` | last night's sleep log (full screen) |

A tile shows `—` until its data has loaded. In mock mode the page is labelled `SAMPLE DATA`; in API mode nothing is sample. The former Track "Today's activity" list (hard-coded rows) was removed. Areas makes no dashboard request of its own; it shares [[Dashboard|Today]]'s.

## Current Frontend

`features/areas/areas_page.dart`, `widgets/area_tile.dart`; destinations `features/study/study_page.dart`, `features/tasks/tasks_page.dart`, `features/goals/goals_page.dart`, `features/track/activity_log_page.dart`, `features/track/sleep_log_page.dart`.

The activity and sleep logging stack (`TrackController`, `TrackRepository`) keeps its `track` name: see [[Phase 5B - Activity and Sleep Logging]], [[Fitness and Activity]], [[Sleep and Recovery]].

## Not here yet

Nutrition and other future areas are not shown until they work. Study has no subjects, exams or sessions of its own yet ([[Study]]).

## Related

[[Dashboard]] · [[Plan]] · [[Insights]] · [[Current Status]]
