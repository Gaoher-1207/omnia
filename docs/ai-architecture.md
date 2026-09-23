# OMNIA AI architecture — Phase 2A

## Request flow

```text
Django authenticated request
  -> AgentRequest(user_id from auth, message, optional proposal ID + token)
  -> semantic router -> fixed category/policy validation
  -> policy-scoped ContextProvider (OMNIA requests only)
  -> ContextManager field filter + shape/size validation + deep freeze
  -> bounded ModelAdapter call -> strict result/action validation
  -> answer / clarification / persisted confirmation proposal
  -> on confirmation: ProposalStore atomically claims stored proposal
  -> ActionExecutor receives trusted claim and rechecks backend authorization
```

General requests use the `general` policy and receive no OMNIA context. The model
chooses one semantic policy from a finite allowlist; it cannot name database
fields or request an arbitrary domain list. Backend policy mappings determine
which fields are eligible for each policy.

## Confirmation and execution trust

The client sends only a proposal ID to Django's authenticated confirmation
flow. It never submits action arguments or a bearer confirmation token. After
explicit user confirmation, Django internally supplies its stored opaque token
to the agent. The trusted Django proposal store must persist the exact action
and arguments, user owner, expiry, token/confirmation state, and idempotency
identity. Its `claim` operation must atomically verify ownership, expiry and
confirmation and enforce one-time use, returning the persisted action with a
trusted confirmation receipt and idempotency key.

The AI module cannot manufacture a trusted claim or grant. The executor receives
the store-produced `ConfirmedAction`; Django must independently recheck user
identity, ownership, permissions, resource state, confirmation receipt, replay,
and idempotency within the domain transaction. Model output only proposes an
action and never authorizes one.

The default proposal store reports `not_connected`; the default executor returns
`not_connected`. Neither persists nor mutates anything.

## OpenAI provider

OpenAI is the first provider, implemented in `ai/agent/openai_adapter.py` behind
the provider-neutral `ModelAdapter`. Both `route_request` and `respond` use the
same injected adapter. The implementation uses strict JSON Schema output via
the Responses API, then converts output text to plain Python mappings for the
existing validators. See [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).

Credentials and deployment-selected model configuration belong in Django's
backend environment: `OPENAI_API_KEY` and `OMNIA_OPENAI_MODEL`. The optional
`OMNIA_OPENAI_MAX_OUTPUT_TOKENS` defaults to 2048. Never place credentials in
Flutter, source control, prompts, logs, or returned errors. The SDK import is
lazy so the provider-neutral package and mock-based tests work without it.

The adapter supplies the configured SDK timeout, disables implicit SDK retries,
checks cancellation before and after synchronous calls, applies the existing
32 KB payload and 8 KB output byte limits, and sets the provider output-token
ceiling. Synchronous cancellation cannot interrupt an in-flight SDK request;
the SDK timeout bounds that request. Rate-limit/connection/server errors map to
the safe `ProviderUnavailable` category; no automatic retry is performed.

## Provider boundary

`ModelAdapter` is provider-neutral. Calls carry a timeout, output limit, and
cancellation event. The coordinator enforces a 32 KB JSON payload limit and an
8 KB default output limit, checks elapsed time and cancellation, and rejects
non-JSON output. A concrete provider must additionally enforce a network/client
timeout and cancellation where supported. Provider failures have typed
exceptions; user responses remain generic and carry an internal category and
correlation ID. No provider is configured in this phase.
