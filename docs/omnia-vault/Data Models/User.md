---
type: data-model
---

# User

## Canonical frontend: `lib/core/models/user.dart`

```dart
class User { String id, email; Profile profile; }   // displayName, timezone, username forward to profile
class Profile { displayName, timezone, username?, studyGoalMinutes, stepGoal,
                taskGoal, sleepGoalMinutes, calorieGoal, WorkoutTime workoutTime; }
```

`User.fromJson` reads the backend's `UserOut`; `Profile.fromJson` reads `ProfileOut` (the whole profile, including the five [[Daily Targets]] and `preferred_workout_time`). Since [[Phase 5A - Profile and Daily Targets]], `Profile.changesSince(before)` builds the changed-fields-only `PATCH /profile` body, and `User.withProfile` keeps the same id and email with the profile the server returned.

`user.id` is the key of the per-user [[Session Architecture|UserSession]].

## Backend: `modules/users/models.py`

- **`User`** (`users`) holds credentials only: `email` (unique), `password_hash` (scrypt), `token_version`.
- **`Profile`** (`profiles`, 1:1, PK = `user_id`) holds `display_name`, `timezone`, `username` (unique, optional), `preferred_workout_time`, and the five [[Daily Targets]].

The docstrings state the split: "Account credentials only. Everything personal lives in Profile or feature tables", and the profile is "Private preferences and daily goals. Never shared with other users."

Related: [[Authentication Flow]] · [[Authentication API]] · [[Profile and Dashboard API]] · [[Data Model Overview]]
