---
type: feature
status: partial
frontend: canonical
backend_available: true
backend_connected: partial
donor: true
---

# Track

The **Track** tab: "Your day at a glance".

## Current Status

`partial`. Tiles from [[Phase 4 - Dashboard API Integration]] (complete); logging and tile taps from [[Phase 5B - Activity and Sleep Logging]] (automated checks pass; manual emulator verification pending):

| Tile | Mock mode | API mode |
|---|---|---|
| Study `… / … goal` | sample `2h 15m`, `4h goal` | ✅ `/dashboard` `today` (not tappable: no real study destination yet) |
| Activity `… / … steps` | sample `6,240`, `8,000 steps`; tap to log (mock) | ✅ `/dashboard` `today`; tap → today's activity log |
| Sleep `… / … goal` | sample `6h 42m`, `8h goal`; tap to log (mock) | ✅ `/dashboard` `today` (**Not logged** when null); tap → last night's sleep log |
| **Tasks** `done of total` | `TaskScope`; tap → Tasks | `TaskScope`; tap → Tasks |
| "Today's activity" list | sample (page labelled `SAMPLE DATA`) | sample, with a `SAMPLE` tag |

The tiles read the **same** `DashboardController` as [[Dashboard|Home]], so Track makes no request of its own.

## Current Frontend

`features/track/track_page.dart`, `widgets/track_tile.dart` (optional `onTap`), `widgets/activity_line.dart`; logging: `activity_log_page.dart`, `sleep_log_page.dart`, `track_controller.dart`, `domain/wellbeing.dart`, `domain/track_repository.dart`, `data/api_track_repository.dart`, `data/mock_track_repository.dart`.

## Backend

Track is the natural home for the per-day logging modules:

- [[Fitness and Activity]] → [[Activity API]]
- [[Sleep and Recovery]] → [[Sleep API]]
- [[Nutrition]] → [[Nutrition API]]
- Study minutes → `/study/sessions` ([[Study API]])

The donor's `TrackRepository` covers all three plus meal photo estimates, with its own logging pages ([[Fawaz Donor Map]]).

## Future Direction

Logging other days, bedtime/wake-time editing, study logging, meals, and a real "Today's activity" list. See [[Backend Integration Roadmap]].

## Related

[[Dashboard]] · [[Insights]] · [[Tasks]]
