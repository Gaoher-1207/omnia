---
type: feature
status: partial
frontend: canonical
backend_available: true
backend_connected: partial
donor: true
---

# Fitness and Activity

## Current Status

`partial`. Since [[Phase 5B - Activity and Sleep Logging]], tapping Activity on [[Dashboard|Home]] or [[Track]] opens a log screen for **today's** steps and workout (done, minutes, type), pre-filled from `GET /activity/{day}` and saved with a whole-day `PUT`; Home and Track then reload. Plan items ("Walk", "Push Workout") are still sample. The long-term [[Goals]] feature can hold a strength goal such as *Incline Dumbbell Press 22.5 / 30 kg*, but it's entered by hand.

## Backend

[[Activity API]] stores **one row per day** (`ActivityDay`): `steps`, `workout_done`, `workout_minutes`, `workout_type`. `PUT /activity/{day}` creates or replaces it. Steps and workouts feed dashboard figures, streaks and achievements (e.g. "Ten workouts", step-goal days).

That's a daily summary, **not** a workout log. The backend has **no** exercises, sets, reps, weights, routines or personal records.

## Current vs future

| Capability | Now | Backend | Planned |
|---|---|---|---|
| Daily steps | ✅ today (5B) | ✅ `/activity` | ✅ |
| Workout done / minutes / type | ✅ today (5B) | ✅ `/activity` | ✅ |
| Routines, exercises, sets/reps/weight | ❌ | ❌ | ✅ |
| Workout history and previous-workout comparison | ❌ | ❌ | ✅ |
| PRs, progression, strength charts | ❌ | ❌ | ✅ |
| Frequency and consistency | ❌ | partial (streaks, counts) | ✅ |
| Fitness goals | via long-term [[Goals]] (manual) | ❌ | ✅ auto-progress |

## Related

[[Fitness Roadmap]] · [[Sleep and Recovery]] (recovery context) · [[Goals]] · [[AI Roadmap]] · [[Achievements and Life Timeline]] (PRs)
