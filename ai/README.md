# OMNIA AI

This package contains a request-scoped assistant coordinator, context minimization
policies, structured-output validation, and replaceable model/backend interfaces.
OpenAI is the first configured provider through `OpenAIModelAdapter`; the core
`ModelAdapter` contract remains provider-neutral so another adapter can replace
it without changing agent orchestration. It does not own authentication,
persistence, or OMNIA domain services.

## Integration status

The default model adapter makes no network calls. The default context provider
returns no user data, the proposal store does not persist, and the action
executor reports `not_connected`. No local mutation is simulated. Inject
configured implementations from the authenticated backend when available.

OpenAI configuration belongs in the backend environment:

- `OPENAI_API_KEY` — required credential; never add it to Flutter, source
  control, prompts, logs, or API responses.
- `OMNIA_OPENAI_MODEL` — required deployment-selected model name.
- `OMNIA_OPENAI_MAX_OUTPUT_TOKENS` — optional output-token ceiling (default
  2048; supported range 1–8192).

The OpenAI SDK is imported lazily. Tests inject a mock client and do not perform
network requests. No dependency manifest exists in this repository; Fawaz should
declare the `openai` SDK in the Django backend's dependency manifest when that
manifest is established.

See `Gaoher/docs/ai-architecture.md`, `ai-contracts.md`, and `ai-context.md` for
the data flow and backend responsibilities.
