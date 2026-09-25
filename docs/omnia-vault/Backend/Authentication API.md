---
type: backend
module: auth
backend_connected: true
---

# Authentication API

`Fawaz/backend/app/modules/auth` · prefix `/api/auth`. It's the **only** backend module the canonical frontend uses. The client side is described in [[Authentication Flow]].

| Endpoint | Body | Response | Notes |
|---|---|---|---|
| `POST /auth/register` | `email`, `password`, `display_name`, `timezone` | **201** `TokenOut` | 409 if the email exists. Rate limited per IP. |
| `POST /auth/login` | `email`, `password` | `TokenOut` | 401 "Incorrect email or password". Rate limited. |
| `GET /auth/me` | none | `UserOut` | Used for session restore |
| `POST /auth/change-password` | `current_password`, `new_password` | `TokenOut` (new token) | **403** on wrong current password. Bumps `token_version`. |
| `POST /auth/logout-all` | none | 204 | `token_version += 1` → every existing token stops working |
| `POST /auth/delete-account` | `password` | 204 | **403** on wrong password. Cascades all user data. |

`TokenOut` = `{access_token, expires_in, user: UserOut}`. `UserOut` = `{id, email, created_at, profile: ProfileOut}`. The profile carries the [[Daily Targets]]. The canonical `User.fromJson` reads only `id`, `email`, `profile.display_name`, `profile.timezone` and `profile.username`. See [[User]].

## Token validity

`common/deps.py` rejects with 401 "Your session has expired or is invalid" when the JWT is expired or badly signed, when `token_version` doesn't match (after a password change or logout-all), or when the user no longer exists. The canonical `ApiClient` turns any such 401 on a request that carried a token into a sign-out ([[Session Architecture]]).

## Security properties

- scrypt hashes (standard library), JWT signed with `AUTH_SECRET`. In production the secret must be at least 32 characters.
- The default lifetime is 720 minutes. **There's no refresh endpoint**, so users re-authenticate after expiry.
- Change password and delete account use 403 on purpose, so a mistyped password doesn't look like an expired session.

Related: [[API Map]] · [[Backend Overview]] · [[Settings]]
