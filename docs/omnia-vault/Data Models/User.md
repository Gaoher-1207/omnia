---
type: data-model
---

# User

## Canonical frontend: `lib/core/models/user.dart`

```dart
class User { String id, email, displayName, timezone; String? username; }
```

`User.fromJson` reads the backend's `UserOut`: `id`, `email`, `profile.display_name`, `profile.timezone`, `profile.username`. The class comment says *"Only what the app uses so far; the profile's daily targets arrive with that feature."*

`user.id` is the key of the per-user [[Session Architecture|UserSession]].

## Backend: `modules/users/models.py`

- **`User`** (`users`) holds credentials only: `email` (unique), `password_hash` (scrypt), `token_version`.
- **`Profile`** (`profiles`, 1:1, PK = `user_id`) holds `display_name`, `timezone`, `username` (unique, optional), `preferred_workout_time`, and the five [[Daily Targets]].

The docstrings state the split: "Account credentials only. Everything personal lives in Profile or feature tables", and the profile is "Private preferences and daily goals. Never shared with other users."

Related: [[Authentication Flow]] · [[Authentication API]] · [[Profile and Dashboard API]] · [[Data Model Overview]]
