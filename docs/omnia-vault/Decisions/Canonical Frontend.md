---
type: decision
status: accepted
---

# Canonical Frontend

## Context

The repository contains two Flutter apps named `omnia_ui`:

- `Shehwaar/omnia_ui`: the frontend developed as the product UI.
- `Fawaz/lib` (with `Fawaz/backend`): a full-stack build whose Flutter side started from an **older** copy of that frontend and was wired to the backend.

Both use the package name `omnia_ui`, and several files are still identical (`Task`, `TaskRepository`, `TaskController`), so it's easy to confuse them.

## Decision

**`Shehwaar/omnia_ui` is the canonical frontend.** `Fawaz/lib` is a **donor / reference implementation**. `Fawaz/backend` is the shared backend for both.

## Reasons

- The canonical app has the newer design and features: long-term [[Goals]] (measurable and completion-only), the app-wide [[Focus]] timer, and accessibility work (screen-reader labels, 200% text, dark-mode contrast, reduced motion) with tests.
- Its architecture already has the integration seams (repository interfaces, `AppDependencies`, `UserSession`, `ApiClient`), so backend work can be added without a rewrite.
- Replacing it with the donor would lose those features and regress the UI.

## Consequences

- Backend functionality is **ported or adapted** into the canonical app feature by feature ([[Mock First API Migration]]). The canonical app isn't replaced.
- Donor code is classified per area in the [[Fawaz Donor Map]] (REUSE / ADAPT, REFERENCE, DO NOT COPY WHOLESALE, INCOMPATIBLE).
- Old donor screens don't replace canonical screens ([[Preserve OMNIA Design System]]).
- Docs and this vault never describe `Fawaz/lib` as "the app".

Related: [[Architecture Decisions]] · [[Architecture Overview]]
