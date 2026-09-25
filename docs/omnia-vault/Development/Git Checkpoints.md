---
type: development
recorded: 2026-09-25
---

# Git Checkpoints

Important local commits on `main`, recorded on 2026-09-25. At that time `origin/main` was at `2fe2269`, **four commits behind** local `main`.

| Commit | Message | Scope |
|---|---|---|
| `527020e` | Document Omnia frontend architecture and setup | `Shehwaar/README.md` only |
| `70864a7` | Add authentication and user sessions | `AuthController`, `timezones`, `User`, `UserSession`, `state_views`, `auth_page`, `settings_page`, `app.dart`; `auth_test` + `fake_auth_backend` |
| `10e8ad2` | Add API infrastructure foundation | `ApiClient`, `ApiConfig`, `ApiException`, `json.dart`, `TokenStore`; Android manifests; `pubspec` (`http`, `flutter_secure_storage`); `api_client_test` |
| `d1e908a` | Implement functional goals tracking | Goal model, controller, pages, Home preview; `goals_test` |
| `2fe2269` | Add Fawaz OMNIA full-stack project | Brought in `Fawaz/` (backend + donor app). This is where `origin/main` currently sits. |

## How to use them

They're **recovery points**. Each one is a known-good state for its milestone (per the README, the auth checkpoint had tests passing, `flutter analyze` clean, and web and debug-APK builds succeeding).

Safe, read-only ways to use them:

```bash
git show --stat 70864a7          # what a checkpoint changed
git diff 70864a7 -- Shehwaar/    # what changed since
git switch --detach 70864a7      # inspect an old state (then: git switch main)
```

> [!warning]
> Hashes are only stable while history isn't rewritten. A rebase, squash or amend before pushing will change them. Refer to phases by **name** in the [[Roadmap]], and treat these hashes as a snapshot of the working history.

Related: [[Roadmap]] · [[Testing]]
