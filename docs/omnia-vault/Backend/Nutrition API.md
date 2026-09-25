---
type: backend
module: nutrition
backend_connected: false
---

# Nutrition API

`modules/nutrition`, table `meals` (migration `0002`).

| Endpoint | Purpose |
|---|---|
| `GET /meals?day=` | Meals and totals for a day (default today) |
| `POST /meals` | Log a meal (`day` defaults to today) |
| `PATCH /meals/{id}` / `DELETE /meals/{id}` | Edit or delete |
| `GET /nutrition/summary?from=&to=` | Daily totals, default 7 days, max 93 |
| `POST /nutrition/estimate` | Estimate from a food photo (JPEG/PNG/WebP). **Not saved.** Returns 503 if no AI provider is configured. |

Meal fields: `meal_type`, `description`, `calories` (0–5000), `protein_g`, `carbs_g`, `fat_g`, `source` (`manual` or `photo_estimate`).

The photo estimator exists only when `AI_PROVIDER=anthropic` and a key is set on the server. The intended flow is to estimate, have the user confirm, then `POST /meals` with `source="photo_estimate"`.

Frontend: [[Nutrition]] (not in the canonical app).

Related: [[API Map]] · [[AI API]]
