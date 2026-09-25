---
type: feature
status: partial
frontend: canonical
backend_available: true
backend_connected: false
donor: true
---

# Track

The **Track** tab: "Your day at a glance", labelled `SAMPLE DATA`.

## Current Status

`partial`.

| Tile | Source |
|---|---|
| Study `2h 15m / 4h goal` | sample |
| Activity `6,240 / 8,000 steps` | sample |
| Sleep `6h 42m / 8h goal` | sample |
| **Tasks** `done of total` | ✅ live, from `TaskScope` |
| "Today's activity" list | sample |

The sample goals (4 h study, 8,000 steps, 8 h sleep) happen to match the backend's default [[Daily Targets]] (240 min, 8000 steps, 480 min).

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

Real figures from `/dashboard` and the logging endpoints, in the canonical Track layout. See [[Backend Integration Roadmap]].

## Related

[[Dashboard]] · [[Insights]] · [[Tasks]]
