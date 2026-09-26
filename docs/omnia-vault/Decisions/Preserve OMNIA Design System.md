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
- **Typography:** Archivo is the product face (titles, body, buttons, values, navigation), set once on the theme. Space Mono is only for short utility text through `OmniaText.label` (small uppercase tags and eyebrows such as `TODAY`, `LAST NIGHT`, `SAMPLE`) and `OmniaText.meta` (dates, times, counts, targets). Both are bundled under `assets/fonts` (OFL), so they never depend on the device or a network fetch.
- Heavy type weights for headings and key figures.
- A fixed pastel category palette (blue, yellow, mint, lilac) with tuned dark-mode variants.
- Light and dark themes from one `buildAppTheme`.
- Shared components: `HardCard`, `SolidAction`, `ActionRow`, `OmniaProgressBar`, `AccentCircle`, `LabelTag`, `OmniaMark`, `AreaHeader`, `SectionHeader`, and the loading, empty (`MessageView`, `EmptyCard`) and error views in `state_views.dart`.
- Form controls: every field uses the theme's `HardInputBorder` (hard outline + offset shadow). Known choices use `SelectField` / `PickerField` / `ChoiceSegments`, never free text: see [[Navigation and Information Architecture]].
- Accessibility is covered by tests: semantics labels, text-scale reflow (`ui_hardening_test`, `goals_test`, `auth_test`), ≥4.5:1 dark-mode contrast (`widget_test`) and reduced-motion onboarding. The README also claims 48 dp touch targets, but no dedicated test for that was found.

## Consequences

- Donor UI is classified **REFERENCE** or **DO NOT COPY** in the [[Fawaz Donor Map]]. Only repositories and mappers are **REUSE / ADAPT**.
- Every integration phase keeps its screens visually unchanged unless there's a deliberate UI task. See the verification list in [[Phase 3 - Tasks API Integration]].
- Sample data is mock-mode only and labelled `SAMPLE`; API mode shows real data or an empty state, never samples.

Related: [[Canonical Frontend]] · [[Flutter Architecture]] · [[Architecture Decisions]]
