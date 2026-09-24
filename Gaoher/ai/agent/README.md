# OMNIA AI Agent

`OmniaAgent` coordinates one request at a time and retains no user context.
Identity comes from the trusted backend request. General conversation receives
no OMNIA context; OMNIA requests use one fixed semantic policy from a finite
category-to-policy map.

Structured model output is untrusted, route checked, size bounded, and strictly
validated. Actions are allowlisted, and only an `action` route can propose one.
The ProposalStore must persist the exact proposal before confirmation is offered.
The client sends only a proposal ID to Django's authenticated confirmation flow;
it cannot submit action arguments or a bearer confirmation token. After explicit
user confirmation, Django internally supplies the stored opaque token to the
agent. The store must atomically verify ownership, expiry, confirmation, and
one-time use before returning the stored proposal, trusted receipt, and
idempotency key.

The AI module cannot manufacture a trusted confirmation claim. Django remains
responsible for authentication, persistence, authorization, ownership/current
state checks, transaction safety, replay protection, and idempotency. The
executor receives the trusted stored claim and independently enforces those
checks.

`OpenAIModelAdapter` is the first provider implementation of the unchanged
`ModelAdapter` protocol. It uses strict JSON Schema responses and translates
provider data/errors into the existing plain mapping and typed-error contracts.
Provider-specific code stays isolated so another provider can replace it later.

The default model adapter makes no provider calls. The default proposal store
does not persist, and the default executor reports `not_connected` without a
mutation. See `Gaoher/docs/ai-architecture.md` for integration details and
backend-only environment configuration.
