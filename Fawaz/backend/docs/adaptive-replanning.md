# Adaptive AI replanning API

Replanning uses the existing authenticated `/api/ai` backend and the existing
daily planner context, provider selection, availability calculation, and
deterministic candidate validator. Ask Omnia remains read-only. Proposal
generation never writes an `AIPlan`; applying a pending proposal creates the
next immutable snapshot revision.

## Endpoints

All endpoints require the normal bearer token.

### Create a proposal

`POST /api/ai/replan/proposals`

```json
{
  "request": "I have an exam tomorrow. Give DBMS more study time.",
  "plan_date": "2026-10-04"
}
```

`plan_date` is optional and defaults to the signed-in user's local today. At
present, replanning is limited to today and requires an existing daily plan.
The `201` response includes proposal ID/status, base plan ID and revision,
typed machine-readable operations, the complete schedule, warnings, a
validation summary, and expiry time. `item_key` identifies a plan item; task
and subject IDs are included only after backend lookup and ownership checks.

### Read a proposal

`GET /api/ai/replan/proposals/{proposal_id}`

Only the owner can read it. Pending proposals past their expiry are reported as
`expired`.

### Apply a proposal

`POST /api/ai/replan/proposals/{proposal_id}/apply`

The backend checks ownership and pending status, locks the owner planning
state, compares the base snapshot/revision and context fingerprint, rejects
past schedule items, reloads context, revalidates the complete schedule, then
creates the next plan revision and marks the proposal applied in one database
transaction. A stale proposal returns HTTP `409` with code
`replan_proposal_stale`. Reuse, dismissal, expiry, or invalid status also
returns a conflict; none changes the active plan.

### Dismiss a proposal

`POST /api/ai/replan/proposals/{proposal_id}/dismiss`

Only a pending proposal can be dismissed. A proposal cannot be applied twice.

## Operation contract

Operations are derived by the backend from the validated base and proposed
schedules; application does not parse model prose. Each has `kind` (`MOVE`,
`RESCHEDULE`, `SHORTEN`, `REMOVE`, `ADD`, or `UNCHANGED`), stable `item_key`,
optional owned `entity_id`, before/after schedule values, and a short reason.
The full `schedule` is authoritative for preview and application. The current
implementation does not emit redundant `UNCHANGED` operations.
The backend independently checks each operation against both schedules and
replays the operation set to ensure it reconstructs the complete proposed
schedule before persisting or applying it.

Explicit instructions that can be checked mechanically, such as moving a
named item to a stated time or increasing a named subject's study allocation,
are verified against the result. Ambiguous natural-language intent is marked
unverified for the user to review; it is never treated as proof of intent.
Future study blocks already present in the base plan are preserved at their
existing subject-level total. Commitments are checked directly as well as
through planner availability intervals.

## Lifecycle

`pending` can transition to `applied`, `dismissed`, `stale`, `expired`, or
`invalid`. Expiry is enforced on read/apply/dismiss; there is no background
expiry worker. A stale proposal is never regenerated or silently overwritten.

## State version and concurrency

`AIPlan` remains append-only. Its per-user/per-day `revision` increases for
normal regeneration and approved replans, with a unique database index on
`(user_id, plan_date, revision)`. The proposal also stores a SHA-256 fingerprint
of its base plan and normalized planner context. Wall-clock movement alone
does not change the fingerprint; application still rejects schedule blocks
that have become past. A shared PostgreSQL owner-row lock serializes generation,
apply, and the task, study, exam, profile, activity, sleep, and commitment
writes that affect planning context.

## Provider behavior and limits

The configured planner provider is reused: OpenRouter supports structured JSON
schema output, Ollama uses its local structured-output mode, and Anthropic
continues to use the configured server-side provider. A provider failure or
malformed response invokes the existing deterministic rules provider to prepare
a clearly warned proposal. The fallback is validated and remains subject to the
same explicit approval and apply checks; if it cannot satisfy a deterministically
checkable request or the planner constraints, the endpoint fails safely without
changing the plan. Chat does not apply plans. A future Ask Omnia integration
should call this same proposal service and let the user approve through the
apply endpoint.

Past plan items have no persisted completion marker. Proposals therefore warn
that past blocks are historical rather than asserting they were completed.

## Client presentation

The Flutter app (`Shehwaar/omnia_ui`) keeps the full contract but shows only a
compact preview: a "Changes to today's plan" heading and one plain sentence per
non-`UNCHANGED` operation (for example, "Moved Assignment from 16:30–17:30 to
18:00–19:00 today"), formatted with the profile's 12/24-hour setting by
`lib/features/plan/replan_change_format.dart`. Summary, explanation, reasons,
the full schedule, warnings, validation data, IDs, and revision numbers stay
out of the normal UI. Apply and Cancel are explicit; closing the preview
dismisses the proposal.
