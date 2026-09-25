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

`partial`. Since [[Phase 4 - Dashboard API Integration]] (complete):

| Tile | Mock mode | API mode |
|---|---|---|
| Study `… / … goal` | sample `2h 15m`, `4h goal` | ✅ `/dashboard` `today` |
| Activity `… / … steps` | sample `6,240`, `8,000 steps` | ✅ `/dashboard` `today` |
| Sleep `… / … goal` | sample `6h 42m`, `8h goal` | ✅ `/dashboard` `today` (**Not logged** when null) |
| **Tasks** `done of total` | `TaskScope` | `TaskScope` |
| "Today's activity" list | sample (page labelled `SAMPLE DATA`) | sample, with a `SAMPLE` tag |

The tiles read the **same** `DashboardController` as [[Dashboard|Home]], so Track makes no request of its own.

## Current Frontend

`features/track/track_page.dart`, `widgets/track_tile.dart`, `widgets/activity_line.dart`. There's no logging UI.

## Backend

Track is the natural home for the per-day logging modules:

- [[Fitness and Activity]] → [[Activity API]]
- [[Sleep and Recovery]] → [[Sleep API]]
- [[Nutrition]] → [[Nutrition API]]
- Study minutes → `/study/sessions` ([[Study API]])

The donor's `TrackRepository` covers all three plus meal photo estimates, with its own logging pages ([[Fawaz Donor Map]]).

## Future Direction

Logging screens in the canonical Track layout, and a real "Today's activity" list. See [[Backend Integration Roadmap]].

## Related

[[Dashboard]] · [[Insights]] · [[Tasks]]
