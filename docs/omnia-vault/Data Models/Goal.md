---
type: data-model
---

# Goal

The **long-term** goal model of the canonical frontend (`lib/features/goals/domain/goal.dart`). It's not related to the backend's daily "goals". See [[Goals vs Daily Targets]].

| Field | Type | Rules |
|---|---|---|
| `id`, `title` | String | non-empty |
| `description` | String? | |
| `category` | `OmniaCategory` | required |
| `targetValue` | double? | null ⇒ **completion-only** |
| `currentValue` | double? | defaults to 0 when measurable. Must be null when completion-only. |
| `unit` | String? | required when measurable, null otherwise |
| `completed` | bool | the user's decision, independent of progress |
| `deadline` | DateTime? | a calendar date (local midnight) |

Derived: `measurable` (target ≠ null) and `percent` = `floor(current × 100 / target)` clamped to 0–100, or null for completion-only goals. Values above the target are kept, so `32.5 / 30 kg` is valid.

The constructor enforces invariants: a positive finite target, a non-negative current value, a non-empty unit, and **no** value or unit for completion-only goals. Tests confirm that older JSON still loads (`goals_test.dart`).

## Not the same as the donor's `Goal`

`Fawaz/lib/features/goals/domain/goal.dart` is a different class: it always requires `targetValue` and `unit`, has **no** `completed` field (`completed => current >= target`), and in the donor it models [[Daily Targets]]. See [[Fawaz Donor Map]].

## Backend

None. A future long-term-goals module needs `current_value`, `target_value`, `unit` (all nullable for completion-only), `completed` (explicit), `deadline`, `category` and `description`. See [[Backend Integration Roadmap]].

Related: [[Goals]] · [[Data Model Overview]]
