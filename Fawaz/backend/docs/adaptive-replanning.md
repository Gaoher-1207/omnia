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

## Blocks added by hand

`POST /api/ai/daily-plan/{date}/items` adds one block (`manual: true`) without a
model. Replanning never sees a manual block as editable: it is left out of the
schedule sent to the provider, counted as busy time (and listed with the fixed
commitments), excluded from the proposal's operations, and copied unchanged into
the applied revision. Regenerating the day keeps manual blocks too.

`DELETE /api/ai/daily-plan/{date}/items/{item_key}` removes any block (manual or
generated) from today's or a later plan as a new revision, so a proposal
prepared before the removal is stale on apply. In the app, removal is offered by
pressing and holding a block's status square, with two confirmations.

## Provider behavior and limits

`PLANNER_AI_PROVIDER` picks the model for proposals:

| Setup | Settings |
|---|---|
| Local demo on your own PC (the launcher's default) | `PLANNER_AI_PROVIDER=ollama`, `ASSISTANT_BASE_URL=http://127.0.0.1:11434`, `ASSISTANT_MODEL=qwen3:8b` (or `OMNIA_AI_*`) |
| Deployment | `PLANNER_AI_PROVIDER=openrouter`, `OPENROUTER_API_KEY`, `OPENROUTER_PRIMARY_MODEL`, `OPENROUTER_FALLBACK_MODEL` |
| No AI | `PLANNER_AI_PROVIDER=rules` (deterministic, offline) |

### The compact edit protocol

The model never rewrites the whole schedule. It sees short keys (`i1`, `i2`…)
for today's blocks and refs (`t1`, `b1`) for tasks and study, and returns only
the changes: `move` (keeps the length), `resize`, `remove` or `add`. The server
copies every untouched block exactly, maps refs back to real ids and rebuilds
the schedule (`app/modules/ai/replan_protocol.py`), then runs the same
authoritative checks as before: free intervals, overlaps, past blocks, exact
task durations, study budgets, required work and the request's explicit
intent. So a model can't invent ids, change unrelated blocks or bypass the
rules. An unknown key, a past block, one block edited twice, or an incomplete
change is rejected, not guessed.

Answers may arrive wrapped in a ```` ```json ```` fence or with prose around
them; the first complete JSON object is used. A cut-off or malformed object is
an error, never patched. Output is capped (700 tokens), and Ollama keeps the
model loaded for 30 minutes.

Measured locally (qwen3:8b on an RTX 4060, 5 requests): 1.5–4.3 s per
proposal, all valid on the first call. Rewriting the whole schedule took
21–39 s, and about one answer in three failed validation.

### Time budget and fallback

One proposal has `REPLAN_TIMEOUT_SECONDS` in total (default 45, range 10–120).
Each AI call gets the time remaining (and never more than the provider's own
timeout).

1. The first AI call.
2. If the answer was malformed or failed the checks, and at least 12 s remain,
   one retry. The retry is told only the short reason code (for example
   `truncated_json`), never user data. Timeouts and outages aren't retried.
3. Otherwise the deterministic rules planner prepares the proposal, with a
   warning saying why: OmniAI "took too long", "didn't pass the schedule
   checks", or "was unavailable". It goes through the same checks.
4. If the rules planner can't satisfy the request either, nothing changes and
   the API returns a clear error:

| Status | `error.code` | When |
|---|---|---|
| 504 | `replan_provider_timeout` | The AI didn't answer within the budget |
| 503 | `replan_provider_unavailable` | Ollama/OpenRouter offline, model missing, or rate limited |
| 422 | `replan_invalid` | The AI's answer failed the checks, and so did the rules attempt |

The app waits up to 60 s, shows "Preparing changes…" meanwhile, and shows the
server's message on failure. Nothing is applied without the user tapping Apply.

Each attempt is logged as `Replan attempt provider=… attempt=… outcome=…
latency_ms=…`, and the `ai.replan.proposal` metric records provider, result,
fallback, attempts, reason and latency. Request text, plan contents, prompts
and keys are never logged. Chat does not apply plans. A future Ask Omnia integration
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
