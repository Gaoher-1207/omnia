---
type: feature
status: sample
frontend: canonical
backend_available: true
backend_connected: false
donor: true
---

# Sleep and Recovery

## Current Status

`sample`. The canonical app shows a sample sleep tile on [[Track]] (`6h 42m / 8h goal`) and sample "Wind Down" items in [[Plan]]. There's no sleep logging.

## Backend (available, not connected)

[[Sleep API]]: one `SleepLog` per night, keyed by the **day the night ends**, with `duration_minutes`, optional `quality`, `bedtime` and `wake_time`. Upsert with `PUT /sleep/{day}`.

Sleep already influences the backend in two ways:

- The dashboard compares it to the profile's `daily_sleep_goal_minutes` ([[Daily Targets]]).
- The AI daily-plan context includes last night's sleep, so the rule-based planner can lighten a day after poor sleep ([[AI API]]).

The donor's `TrackRepository` and `log_pages.dart` log sleep ([[Fawaz Donor Map]]).

## Future Direction

- Sleep logging in the canonical Track design.
- Recovery context for training and workload recommendations (vision): see [[AI Roadmap]] and [[Fitness Roadmap]].

## Related

[[Fitness and Activity]] · [[Plan]] · [[Dashboard]]
