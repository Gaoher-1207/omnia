---
type: decision
status: accepted
---

# Preserve OMNIA Design System

## Context

The donor app has working screens for many backend features (Plan, Study, Track logging, Social). They're built on an **older** version of the OMNIA theme and widgets.

## Decision

**Port functionality and data integration. Don't port old screens.** New and backend-connected features are built from the canonical design system.

## The canonical design system (`lib/core/theme`, `lib/core/widgets`)

- A neo-brutalist look with an indigo/violet identity: thick outlines and unblurred offset "hard" shadows (`SurfaceStyle`, `SurfaceShadow`, `HardCard`).
- Heavy type weights for headings and key figures.
- A fixed pastel category palette (blue, yellow, mint, lilac) with tuned dark-mode variants.
- Light and dark themes from one `buildAppTheme`.
- Shared components: `HardCard`, `SolidAction`, `ActionRow`, `OmniaProgressBar`, `AccentCircle`, `LabelTag`, `OmniaMark`, and the loading, empty and error views in `state_views.dart`.
- Accessibility is covered by tests: semantics labels, text-scale reflow (`ui_hardening_test`, `goals_test`, `auth_test`), ≥4.5:1 dark-mode contrast (`widget_test`) and reduced-motion onboarding. The README also claims 48 dp touch targets, but no dedicated test for that was found.

## Consequences

- Donor UI is classified **REFERENCE** or **DO NOT COPY** in the [[Fawaz Donor Map]]. Only repositories and mappers are **REUSE / ADAPT**.
- Every integration phase keeps its screens visually unchanged unless there's a deliberate UI task. See the verification list in [[Phase 3 - Tasks API Integration]].
- Screens that stay on sample data keep their on-screen `SAMPLE` labels until real data arrives.

Related: [[Canonical Frontend]] · [[Flutter Architecture]] · [[Architecture Decisions]]
