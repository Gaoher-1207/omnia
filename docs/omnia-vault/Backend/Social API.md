---
type: backend
module: social
backend_connected: false
---

# Social API

`modules/social` · prefix `/api/social` (migration `0003`). **There's no canonical frontend feature for it.** The donor app has full social screens ([[Fawaz Donor Map]]: REFERENCE).

| Area | Capabilities |
|---|---|
| Discovery | Look up a user by exact `username` (set on the profile) |
| Friends | Request, accept, decline, unfriend or cancel. List friends and pending requests. |
| Groups | Create (owner), rename, delete, add a friend as member, leave or remove a member |
| Group chat | List messages (`after` for polling, `limit` ≤200), send |
| Feed & posts | Feed from me, friends and groups. Post progress, an achievement or a note. Like or unlike. Delete. |
| Challenges | Per-group challenges with a `metric`, `target` and date range. Join or leave. Leaderboard. |

Tables: `friendships`, `social_groups`, `group_members`, `group_messages`, `posts`, `post_likes`, `challenges`, `challenge_participants`.

Not on the near-term [[Roadmap]]. It needs `username` editing in [[Settings]] first.

Related: [[API Map]] · [[Achievements and Life Timeline]] (posts can share achievements)
