---
type: feature
status: partial
frontend: canonical
backend_available: true
backend_connected: true
donor: true
---

# Insights

## Current Status

**Workouts and steps are implemented** (October 11, uncommitted). A Week/Month switch shows the calendar week (Monday–Sunday) or month around today. Each of two cards, **Workouts** and **Steps**, has a headline figure, a one-line detail and a compact habit grid (Monday-first columns, one square per day):

- filled = workout logged / step goal reached; outlined = logged without it; dotted = **not logged**; faint = still to come.
- Figures use logged days only. An unlogged day is never treated as zero, and the page says how many days weren't logged. With fewer than three logged days it gives counts but no rates; with none it shows "Nothing logged this week yet."
- Each day has a screen-reader label ("Monday, September 21: workout, 45 minutes"). The grid fits 320 px at 200% text in both themes.
- Data: `GET /api/activity?from&to` (`TrackRepository.activityHistory`), dropping the server's `id: null` placeholders so they aren't counted. It reloads after an activity log is saved elsewhere and on pull to refresh. Mock mode uses the in-memory sample day and keeps the `SAMPLE DATA` label.

A third card, **Study**, shows minutes and days studied (Focus sessions, plan check-offs and logged study, from `GET /study/sessions`), with the split by source. A day without study is "no study recorded" — study has no separate "not logged" state.

Not yet: sleep and task insights, and the streak/progress views from [[Progress API]].

## Planned direction

Replace the empty state with weekly and monthly views of logged activity, starting with gym/workout consistency and steps. The visual reference is a compact habit-history grid (small day markers that make patterns easy to scan), adapted to OMNIA's existing neo-brutalist design rather than copying another app's styling. Keep the page's current title and empty state until real data is connected; never fabricate activity metrics in API mode.

**Code:** `features/insights/insights_page.dart`, `activity_insights.dart` (pure figures, tested), `widgets/habit_grid.dart`.

## Backend (available, not connected)

[[Progress API]]:

- `GET /progress?days=1..90` returns four streaks (`study`, `tasks`, `fitness`, `balance`, each with current, longest and active-today) plus a daily history (study minutes, tasks completed, steps, workout, balanced, sleep, calories).
- `GET /achievements` returns 12 fixed achievement definitions with progress. See [[Achievements and Life Timeline]].

The donor's `ProgressRepository` wraps both ([[Fawaz Donor Map]]).

## Dependency

Insights only becomes meaningful once real data flows in from [[Tasks]], [[Study]], [[Fitness and Activity]] and [[Sleep and Recovery]]. That's why it comes late on the [[Backend Integration Roadmap]].

## Related

[[Areas]] · [[Dashboard]] · [[AI Roadmap]]
