# Backend compatibility checklist

Use this to confirm that a backend (a new deployment, a teammate's branch, a different implementation) works with the canonical frontend. The contract is in [`API_CONTRACT.md`](API_CONTRACT.md); how to run the app is in [`README.md`](README.md).

## 1. Reachability

- [ ] `GET <base>/health` answers `200` from the machine the app runs on (`run_frontend.ps1 -Api -BaseUrl <base> -DryRun` checks it).
- [ ] The base URL ends in `/api` and the paths below resolve under it.
- [ ] Physical phone: the backend listens on `0.0.0.0` (not `127.0.0.1`) and the port is open in the firewall.
- [ ] Release builds: the URL is `https://`.
- [ ] Web: the page's origin is in the backend's allowed CORS origins.

## 2. API checks (no app needed)

Swagger (`<base>/docs` on the reference backend) or any HTTP client:

- [ ] `POST /auth/register` returns `access_token` and `user.profile` with every `Profile` field; a second register with the same email is refused with an error envelope.
- [ ] `POST /auth/login` with a wrong password returns `401`; with the right one, a token.
- [ ] `GET /auth/me` with the token returns the same `user`; without it, `401`.
- [ ] `PATCH /profile` with one field changes only that field and returns the whole `Profile`.
- [ ] `GET /dashboard` returns `date`, `greeting`, `display_name`, `today.*` and `next_exam` (object or `null`); `today.sleep_minutes` is `null` before any sleep is logged.
- [ ] `GET /tasks?limit=200&offset=0` returns `{ items, total }`; `POST`, `PATCH` (including `{ "status": "done" }`) and `DELETE /tasks/{id}` work.
- [ ] `GET /activity/{today}` on an empty day returns zeros (not `404`); `PUT` with all four fields replaces the day; `PUT` for tomorrow is refused with `422` and a `details` entry.
- [ ] `POST /study/subjects` then `GET /study/subjects` lists it; the same name again is refused with `409`; `POST /study/exams` for that subject appears in `GET /study/exams` (with `days_left`) and as `next_exam` on `GET /dashboard`; deleting the subject removes its exams.
- [ ] `GET /sleep/{today}` on an empty night returns `"logged": false`; `PUT` then `GET` returns `"logged": true`; `DELETE` removes it.
- [ ] Errors use the `{ "error": { code, message, details[] } }` envelope, with `details[].field` naming the input (e.g. `body.steps`).
- [ ] Two accounts never see each other's tasks, activity, sleep or profile.

## 3. In the app (API mode)

Start with `.\integration\run_frontend.ps1 -Api -BaseUrl <base>` (or the `flutter run` equivalent).

- [ ] Register a new account; Today greets you by name with the server's date. No `SAMPLE` label appears anywhere.
- [ ] Sign out and sign in again; quit and relaunch: still signed in.
- [ ] Settings → Profile & daily targets: change the study target; Today's Study card target changes at once.
- [ ] Tasks: add (with a preset estimate and a due date), complete, edit, delete. Counts on Today and Areas follow.
- [ ] Activity: log steps and a workout (preset type, then Other); Today updates at once; reopen: values kept.
- [ ] Sleep: log `7h 30m`, quality 4; remove it; Today shows **Not logged**.
- [ ] Areas → Study: add a subject, then an exam for it (subject picked, not typed). Today shows the exam; after a relaunch, both are still there. Delete the exam: Today says "No exams coming up."
- [ ] Plan says "No plan yet."; Insights says "No insights yet"; Goals starts empty and says it isn't synced.
- [ ] Turn the backend off: the app shows "Can't reach OMNIA…" errors and keeps what you typed; turn it on and retry.
- [ ] Revoke the session (e.g. Sign out everywhere from another device): the next request returns you to sign-in.

## 4. Known gaps (not failures)

- Plan has no real plan until `/ai/daily-plan` is connected (Phase 5C).
- Long-term Goals are local only: no backend endpoint exists.
- Study manages subjects and exams only; backlog, logged sessions and the study plan aren't shown yet.
- Insights doesn't read `/progress` yet.
- iOS and macOS API mode are untested and need platform network settings (see README).

A backend passing sections 1–3 is compatible with the current frontend.
