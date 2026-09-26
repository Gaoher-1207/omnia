---
type: feature
status: partial
frontend: canonical
backend_available: true
backend_connected: true
donor: true
---

# Sleep and Recovery

## Current Status

`partial`. Since [[Phase 5B - Activity and Sleep Logging]], tapping Sleep on [[Dashboard|Home]] or [[Track]] opens a log screen for the night ending **today**: hours and minutes plus an optional 1–5 quality, pre-filled from `GET /sleep/{day}`, saved with a whole-day `PUT` that sends any stored bedtime and wake time back unchanged, and removable (with confirmation) via `DELETE`, after which Home shows **Not logged**. Bedtime and wake time aren't editable yet. "Wind Down" items in [[Plan]] are still sample.

## Backend

[[Sleep API]]: one `SleepLog` per night, keyed by the **day the night ends**, with `duration_minutes`, optional `quality`, `bedtime` and `wake_time`. Upsert with `PUT /sleep/{day}`.

Sleep already influences the backend in two ways:

- The dashboard compares it to the profile's `daily_sleep_goal_minutes` ([[Daily Targets]]).
- The AI daily-plan context includes last night's sleep, so the rule-based planner can lighten a day after poor sleep ([[AI API]]).

The donor's `TrackRepository` and `log_pages.dart` log sleep ([[Fawaz Donor Map]]).

## Future Direction

- Recovery context for training and workload recommendations (vision): see [[AI Roadmap]] and [[Fitness Roadmap]].

## Related

[[Fitness and Activity]] · [[Plan]] · [[Dashboard]]
