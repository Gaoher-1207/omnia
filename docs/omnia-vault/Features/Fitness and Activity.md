---
type: feature
status: sample
frontend: canonical
backend_available: true
backend_connected: false
donor: true
---

# Fitness and Activity

## Current Status

`sample`. In the canonical app, activity appears only as sample figures on [[Track]] and [[Dashboard]] and as sample Plan items ("Walk", "Push Workout"). There are no workout or step-logging screens. The long-term [[Goals]] feature can hold a strength goal such as *Incline Dumbbell Press 22.5 / 30 kg*, but it's entered by hand.

## Backend (available, not connected)

[[Activity API]] stores **one row per day** (`ActivityDay`): `steps`, `workout_done`, `workout_minutes`, `workout_type`. `PUT /activity/{day}` creates or replaces it. Steps and workouts feed dashboard figures, streaks and achievements (e.g. "Ten workouts", step-goal days).

That's a daily summary, **not** a workout log. The backend has **no** exercises, sets, reps, weights, routines or personal records.

## Current vs future

| Capability | Now | Backend | Planned |
|---|---|---|---|
| Daily steps | sample | ✅ `/activity` | ✅ |
| Workout done / minutes / type | sample | ✅ `/activity` | ✅ |
| Routines, exercises, sets/reps/weight | ❌ | ❌ | ✅ |
| Workout history and previous-workout comparison | ❌ | ❌ | ✅ |
| PRs, progression, strength charts | ❌ | ❌ | ✅ |
| Frequency and consistency | ❌ | partial (streaks, counts) | ✅ |
| Fitness goals | via long-term [[Goals]] (manual) | ❌ | ✅ auto-progress |

## Related

[[Fitness Roadmap]] · [[Sleep and Recovery]] (recovery context) · [[Goals]] · [[AI Roadmap]] · [[Achievements and Life Timeline]] (PRs)
