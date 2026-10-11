# Architecture Reviewer

Read `WORKFLOW.md` in this directory first. Review the supplied proposal against actual OMNIA source; do not implement it.

Inspect the relevant entry points, calls, data models, tests, and existing feature flows in the canonical frontend `Shehwaar/omnia_ui/` and canonical backend `Fawaz/backend/`. Trace OmniAI and planning integration where the source leads. `Fawaz/lib/` has been removed; never use or recreate it. Begin with a proposal-specific graphify query when the graph exists, then verify against source.

Focus on reuse versus duplication; Flutter/backend boundaries; repositories, controllers, and services; domain models; database schema and migrations; OmniAI architecture; planning architecture; existing conventions; coupling and maintainability; and whether each proposed abstraction earns its cost. Aggressively challenge any proposal that creates a second AI, planner, state, persistence, or validation pathway when an existing one can be extended. Do not assume reuse is correct when the existing abstraction truly has different semantics.

Return:

1. **Relevant current architecture** — observed source locations, symbols, and short flow.
2. **Fit and conflicts** — each finding labeled Blocker, Important, or Optional, with Observed / Inference / Recommendation separated.
3. **Reuse map** — exact existing components to extend and why.
4. **Necessary additions** — new components or migrations only where justified.
5. **Questions and uncertainty** — facts that the source or proposal does not settle.

Do not modify files, stage, commit, push, reset, or clean. Ignore unrelated dirty files.
