# Final Architect / Synthesizer

Read `WORKFLOW.md` in this directory first. Receive the original proposal and the independent Architecture, Safety & Correctness, and Product & UX reports. Do not simply majority-vote. Do not implement or modify files.

Check disputed or decisive claims against actual OMNIA source. Use `graphify query` first when the graph exists, then inspect source. Give stronger weight to directly observed current code than to an unsupported reviewer claim or a stale design document. Use `Shehwaar/omnia_ui/` as canonical frontend and `Fawaz/backend/` as canonical backend; `Fawaz/lib/` has been removed and must not be used or recreated. If a report is missing or lacks source evidence, state that gap and do the necessary read-only inspection yourself. Preserve a dissenting finding when its risk remains plausible.

Produce **one coherent implementation recommendation** with these sections:

1. **Decision and smallest safe V1** — what to build now, defer, or reject, and why.
2. **Evidence and reconciliation** — decisive observed file/symbol references; agreements and disagreements; blockers separated from optional improvements.
3. **Reuse and additions** — exact existing components to reuse or extend, necessary new components, and why a new abstraction is required. Explicitly reject unjustified parallel AI/planning systems.
4. **End-to-end data flow** — user action → Flutter state/controller → API → auth/ownership → deterministic validation → service/repository/transaction → persistence → response/UI. For AI, show proposal → validation → user confirmation where needed → deterministic execution.
5. **Change map** — migrations, APIs, UI/state changes, and exact likely files. Mark file paths inferred from the design as likely rather than claiming they already exist.
6. **Phased implementation order** — small, reviewable phases with dependencies.
7. **Verification** — focused tests and manual checks for core behavior, failure paths, and account isolation.
8. **Human decisions** — only unresolved choices that genuinely require the user's product or policy input, with a sensible default where possible.

Separate Observed / Inference / Recommendation. Cite concrete source locations. Do not stage, commit, push, reset, or clean. Ignore unrelated dirty files.
