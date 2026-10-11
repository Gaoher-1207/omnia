# OMNIA Engineering Council

Use this council to review a proposed major architectural change **before implementation**. It is a technical design review, not startup or market validation. The existing source is authoritative; a proposal and repository documentation are hypotheses until checked against code.

## Scope and source of truth

- Canonical Flutter frontend: `Shehwaar/omnia_ui/`.
- Canonical backend: `Fawaz/backend/`.
- `Fawaz/lib/` (the old Flutter app) has been removed; `Shehwaar/omnia_ui/` is the only frontend.
- Inspect relevant OmniAI and planning code wherever the current integration actually lives; verify ownership from imports, calls, routes, and tests rather than assuming a document is current.
- Start codebase discovery with `graphify query "<proposal-specific question>"` when `graphify-out/graph.json` exists. Use `graphify path` or `graphify explain` for focused follow-up. Use `graphify-out/wiki/index.md` for broad navigation if it exists. Then inspect actual source with line references. A graph result is a pointer, not proof of current behavior.
- Do not modify application code or any other file while reviewing. Do not stage, commit, push, reset, or clean. Ignore unrelated dirty working-tree files.

## Run sequence

Run the parent session in a read-only or plan permission mode where available. Parent-level live permission overrides can supersede an agent file's read-only setting; do not run this council in an elevated editing mode.

1. Preserve the feature proposal verbatim. Identify assumptions or missing details without replacing the user's intent.
2. Start `omnia_architecture_reviewer`, `omnia_safety_correctness_reviewer`, and `omnia_product_ux_reviewer` with the **same proposal** and their own role instructions. Give none of them another specialist's findings. Run them in parallel when native read-only subagents are available. Otherwise run them sequentially in isolated contexts; do not share findings until all three finish.
3. Wait for all three complete reviews. Keep each report intact, including source references, uncertainties, and dissent. If a specialist cannot inspect source, record that limitation rather than inventing evidence.
4. Give the proposal and all three reports to `omnia_final_architect`. It reconciles them, checks contested claims against source as needed, and produces one recommendation. The parent returns that recommendation, with any material evidence limitations.

The parent orchestrates the agents. The Final Architect does not need to spawn the specialists, so this works even when nested subagents are unavailable. If named agents cannot be loaded, use the tooling's native general-purpose subagents with the matching role files in this directory. If subagents are unavailable altogether, report that the council cannot run as an independent multi-agent review in that session; do not present one agent's sequential self-review as four independent reports.

## Evidence and review standard

Every specialist must inspect actual source before making an architectural claim. Cite concrete paths and classes, functions, or line numbers. Label **Observed**, **Inference**, and **Recommendation** so a reader can tell what the code does from what the reviewer proposes. Use repository-specific evidence over generic advice. State when a relevant path was not inspected. Keep the design aligned with OMNIA's deterministic validation philosophy and avoid parallel AI or planning architectures.

Use severity sparingly: **Blocker** means unsafe or incoherent to implement as proposed; **Important** means needed for a sound V1; **Optional** means a later improvement. Do not call a speculative edge case a blocker without an end-to-end failure path.

## Invocation

From the repository root, in Codex or Claude Code:

> Run the OMNIA engineering council on this proposal: `<feature description>`. Follow `.agents/omnia-engineering-council/WORKFLOW.md`. Have `omnia_architecture_reviewer`, `omnia_safety_correctness_reviewer`, and `omnia_product_ux_reviewer` review the same proposal independently, in parallel if supported. Wait for all three reports, then give them to `omnia_final_architect` for one final design recommendation. This is read-only; do not implement or change files.
