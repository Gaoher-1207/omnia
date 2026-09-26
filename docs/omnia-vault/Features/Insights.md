---
type: feature
status: sample
frontend: canonical
backend_available: true
backend_connected: false
donor: true
---

# Insights

## Current Status

Not implemented. The **Insights** tab shows an empty state, "No insights yet", explaining they aren't connected. No charts or figures are drawn (mock mode only adds a `SAMPLE DATA` label).

**Code:** `features/insights/insights_page.dart`, with no controller or repository.

## Backend (available, not connected)

[[Progress API]]:

- `GET /progress?days=1..90` returns four streaks (`study`, `tasks`, `fitness`, `balance`, each with current, longest and active-today) plus a daily history (study minutes, tasks completed, steps, workout, balanced, sleep, calories).
- `GET /achievements` returns 12 fixed achievement definitions with progress. See [[Achievements and Life Timeline]].

The donor's `ProgressRepository` wraps both ([[Fawaz Donor Map]]).

## Dependency

Insights only becomes meaningful once real data flows in from [[Tasks]], [[Study]], [[Fitness and Activity]] and [[Sleep and Recovery]]. That's why it comes late on the [[Backend Integration Roadmap]].

## Related

[[Areas]] · [[Dashboard]] · [[AI Roadmap]]
