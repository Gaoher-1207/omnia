# OMNIA AI contracts — Phase 2A

## Authenticated request

`AgentRequest.user_id` is populated by trusted Django authentication, never from
client-controlled identity or model output. The client sends a proposal ID to
the authenticated Django confirmation endpoint. After explicit confirmation,
Django internally constructs the agent request with its backend-held opaque
confirmation token. The request cannot contain replacement action arguments;
clients must never provide the token directly.

## Routing and context

The model returns exactly `{category, policy}`. Categories are `general`,
`omnia`, and `action`. Policy is a single finite identifier permitted for that
category. General maps only to `general`; action currently maps to the narrower
`task_action` policy. The model cannot provide field names or a domain list.

The ContextProvider accepts authenticated user identity and a policy ID. Django
must map that ID to a fixed, authorized query. ContextManager filters allowed
fields, validates JSON shape, nesting, sensitive nested keys and size, then
returns recursively immutable values. The model adapter receives a fresh plain
JSON copy.

## Model adapter

`generate_structured(task, payload, options=ModelCallOptions(...))` returns
untrusted mapping output. Options include a client timeout, output byte limit,
and optional cancellation event. The coordinator caps serialized payloads at
32 KB, defaults output to 8 KB, and checks elapsed timeout, cancellation, and
JSON serializability. Provider implementations must enforce an actual transport
timeout and cancellation where supported. Typed failures distinguish timeout,
unavailable provider, malformed structured output, cancellation, and limits.

`OpenAIModelAdapter` implements the same protocol through the OpenAI Responses
API. It supports only the named `route_request` and `respond` tasks, uses strict
JSON Schema, and converts the response's JSON text to a plain mapping. Refusals,
empty output, invalid JSON, and provider exceptions become safe typed failures.
The adapter does not expose provider exception messages. It sets a real SDK
timeout, disables automatic retries, checks cancellation before/after the
synchronous request, and honors the existing byte caps plus a model output-token
ceiling. Provider rate-limit, connection, and server failures map to
`ProviderUnavailable`; retry policy stays bounded and explicit at a future
backend boundary.

Required backend environment variables: `OPENAI_API_KEY` and
`OMNIA_OPENAI_MODEL`. Optional: `OMNIA_OPENAI_MAX_OUTPUT_TOKENS` (default 2048,
allowed range 1–8192). The key must never enter Flutter, source control, prompts,
logs, or user-facing errors.

The default adapter makes no network calls. No provider SDK dependency manifest
exists here; Django should declare the `openai` package in its own dependency
manifest when available. Other providers can implement `ModelAdapter` without
changing these request/response contracts.

## Action and confirmation contracts

The immutable registry currently permits `create_task(title, due_at?)` and
`reschedule_task(task_id, new_due_at)`, both requiring confirmation and bound to
the `task_action` context policy. Model output is accepted only for action names
permitted by the validated route policy and after strict argument validation.

The ProposalStore must persist the exact proposal and expiry before the agent
offers confirmation. `claim(user_id, proposal_id, confirmation_token, now)` must
atomically check the authenticated owner, original arguments, expiry,
confirmation state, and unused status. It returns a `ConfirmedAction` containing
the persisted proposal, trusted receipt, and stable idempotency key. The AI
module does not create grants or trust action data from the confirmation
request. The store must reject forged tokens, other users, expired proposals,
and replays.

ActionExecutor returns `ExecutorResult` with one of `success`, `denied`,
`failed`, `not_connected`, or `ambiguous`. Django must reauthorize independently
and use proposal identity for idempotency. `ambiguous` means the caller must
check status by idempotency key before retrying. Exceptions during execution are
treated as ambiguous because commit state may be unknown.

## Safe errors

`AgentResponse.error` contains a stable internal category and correlation ID.
The user-facing message does not include exception text, prompts, provider
secrets, database details, or infrastructure details. Django may log the
category and ID with appropriate privacy controls; raw secrets and prompts must
not be logged.
