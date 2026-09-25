---
type: feature
status: planned
frontend: none
backend_available: true
backend_connected: false
donor: true
---

# Nutrition

## Current Status

`planned`. The canonical frontend has **no** nutrition UI. The only traces are the `nutrition` value in `OmniaCategory` and the sample "Lunch" item in [[Plan]].

## Backend (available, not connected)

[[Nutrition API]]:

- `Meal` rows per day: `meal_type`, `description`, `calories`, `protein_g`, `carbs_g`, `fat_g`, `source` (`manual` or `photo_estimate`).
- `GET /meals?day=` returns the meals plus day totals, and `GET /nutrition/summary` gives totals over a range.
- `POST /nutrition/estimate` estimates a meal from a food photo. It **stores nothing**, needs an AI provider configured on the server, and returns **503** otherwise.
- Daily calories are compared against `daily_calorie_goal` ([[Daily Targets]]).

The donor has `meals_page.dart` and the meal methods in `TrackRepository` ([[Fawaz Donor Map]]).

## Future Direction

Meal logging inside the canonical [[Track]] design, after activity and sleep. It isn't a near-term phase on the [[Roadmap]].

## Related

[[Track]] · [[Dashboard]] · [[AI Assistant]] (photo estimate is the only AI-backed nutrition feature, server-side)
