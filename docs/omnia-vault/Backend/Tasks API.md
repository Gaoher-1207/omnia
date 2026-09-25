---
type: backend
module: tasks
backend_connected: false
---

# Tasks API

`Fawaz/backend/app/modules/tasks` · prefix `/api/tasks`. It's the target of [[Phase 3 - Tasks API Integration]].

| Endpoint | Request | Response |
|---|---|---|
| `GET /tasks` | query: `status` (`todo` / `done`), `priority`, `due_on_or_before`, `limit` (1–200, default 50), `offset` | `Page[TaskOut]` = `{items, total, limit, offset}` |
| `POST /tasks` | `TaskCreate` | **201** `TaskOut` |
| `GET /tasks/{id}` | none | `TaskOut` |
| `PATCH /tasks/{id}` | `TaskUpdate` (partial; "including completing it") | `TaskOut` |
| `DELETE /tasks/{id}` | none | 204 |

## Schemas

- **TaskCreate:** `title` (≤200), `notes` (≤2000), `priority` (`low` / `medium` / `high`, default `medium`), `due_date`, `due_time` (**needs** `due_date`), `estimated_minutes` (1–1440), `category` (`study`, `tasks`, `activity`, `sleep`, `nutrition`, `habits`)
- **TaskUpdate:** the same fields plus `status`. `title`, `priority`, `status` and `category` can't be null.
- **TaskOut:** adds `id` (UUID), `status`, `completed_at`, `created_at`, `updated_at`

The server assigns ids. Unknown fields are rejected. Another user's task returns **404**. Indexes on `(user_id, status, due_date)` and `(user_id, completed_at)`.

## Mapping to the canonical Task

The canonical [[Task]] model differs in shape. The donor `ApiTaskRepository` already maps it:

| Canonical `Task` | Backend | Mapping |
|---|---|---|
| `id` (client string) | `id` UUID (server) | use the returned id |
| `description` | `notes` | rename |
| `completed: bool` | `status: todo/done` | bool ↔ enum |
| `priority: normal` | `priority: medium` | `normal ↔ medium` |
| `dueAt: DateTime?` | `due_date` + `due_time` | local 00:00 ⇒ date only ("all day") |
| `estimatedDuration` | `estimated_minutes` | seconds are dropped. Under 1 min ⇒ null. |
| `category` | `category` | same six names |
| `createdAt` | `created_at` | parse |

Side effects elsewhere: completed tasks feed the dashboard `tasks_completed`, the `tasks` streak, and the "Getting things done" achievements. Open tasks feed the AI plan context (titles only) and the calendar feed (when they have a due date).

Related: [[Tasks]] · [[API Map]] · [[Fawaz Donor Map]]
