---
type: data-model
---

# Task

## Canonical frontend: `lib/features/tasks/domain/task.dart`

| Field | Type | Rules |
|---|---|---|
| `id` | String | non-empty; caller-supplied for now |
| `title` | String | non-empty |
| `description` | String? | |
| `completed` | bool | default false |
| `priority` | `TaskPriority` { low, normal, high } | default normal |
| `createdAt` | DateTime | |
| `dueAt` | DateTime? | local 00:00 is treated as "all day" in the UI |
| `estimatedDuration` | Duration? | non-negative |
| `category` | `OmniaCategory` | default `tasks` |

Immutable. `copyWith` distinguishes "omitted" from explicit `null` through an `_unchanged` sentinel. `toJson` uses camelCase and is **not** the backend format.

The donor `Fawaz/lib` `Task` is identical, apart from line endings.

## Backend: `modules/tasks/models.py`

`tasks`: `id` UUID, `user_id` FK (cascade), `title` ≤200, `notes`, `priority` (low / medium / high), `status` (todo / done), `due_date`, `due_time`, `estimated_minutes` 1–1440, `category`, `completed_at`, `created_at`, `updated_at`. CHECK constraints mirror the enums.

## Mapping

See the mapping table in [[Tasks API]]. The key differences are `normal↔medium`, `description↔notes`, `completed↔status`, `dueAt↔due_date+due_time`, and server-assigned UUIDs.

Related: [[Tasks]] · [[Phase 3 - Tasks API Integration]] · [[Data Model Overview]]
