# OMNIA AI context policy — hardened Phase 1

Context retrieval is backend controlled. The model may select one semantic
policy from the route allowlist; it cannot choose fields, table names, or an
unrestricted list of domains. Django must independently map policy identifiers
to fixed queries scoped to the authenticated user.

| Policy | Permitted fields |
|---|---|
| General | None |
| Study | Exams, study progress, tasks, preferences |
| Productivity | Tasks, goals, preferences, recent plan |
| Task action | Tasks, preferences |
| Fitness | Activity, fitness, preferences |
| Food | Nutrition, preferences |
| Sleep | Sleep, preferences |
| Goals | Goals, recent feedback, preferences |
| Progress | Study progress, activity, fitness, sleep, nutrition, goals |
| Other | None |

The category-to-policy allowlist is enforced by the AI module: `general` only
permits `general`; `omnia` permits one of the domain policies; `action` currently
permits only `task_action`. Add policies only with explicit field rules and
backend query behavior.

ContextManager drops unrelated top-level keys. Selected values must be JSON
compatible and fit the fixed 24 KB total / 8 KB per-field budgets, five-level
nesting limit, and item-count limit. Unsupported values and sensitive nested
keys (credentials, tokens, prompts, infrastructure identifiers, and similar)
are rejected. Selected values are recursively frozen before use and copied to
plain JSON containers only at the model call boundary.

Never send credentials, provider tokens, internal prompts, database or
infrastructure details, or another user's data. Django remains responsible for
user scoping and for limiting broad fields such as preferences to the minimum
subfields needed for the selected policy.
