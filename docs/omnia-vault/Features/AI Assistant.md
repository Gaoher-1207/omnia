---
type: feature
status: partial
frontend: canonical
backend_available: partial
backend_connected: true
---

# AI Assistant

> [!info] What exists today
> **Ask Omnia** (`ed47dac`) is a read-only, context-aware assistant: in API mode it calls `POST /ai/chat` and answers from the user's own data; it never creates, edits or applies anything. AI **planning** lives in [[Plan]]: the daily plan (AI-assisted with a deterministic rules fallback) and adaptive replanning proposals that change nothing until the user taps Apply. Mock mode uses canned sample answers. Cross-domain learning and recommendations below are still vision.

## What exists in the backend today

> [!note] This section predates Ask Omnia and replanning. The backend now also serves `POST /ai/chat` (read-only assistant), `/ai/replan/proposals*` (validated, explicitly applied plan changes), and Ollama and OpenRouter planner providers besides `rules` and `anthropic`.

The [[AI API]] (`modules/ai`) originally generated **one kind of output: a daily plan**.

- The default provider is `rules`, a deterministic rule-based planner that works offline with no key.
- An optional `anthropic` provider is set on the **server** via `AI_PROVIDER`, `AI_API_KEY` and `AI_MODEL`. If it fails, the rules provider answers and `is_fallback = true`.
- Context is deliberately minimal and anonymised: the [[Daily Targets]], today's and yesterday's totals, streaks, upcoming exams, study blocks, open task titles (as refs like `t1`), last night's sleep and an optional note. Email, name, ids, task notes and deep history are never sent.
- Separately, `POST /nutrition/estimate` estimates a meal from a photo with the same provider (see [[Nutrition]]).

So "AI" in the backend means **plan generation plus one estimator**. There is no conversational assistant, no memory and no cross-module learning.

## The product vision

OMNIA's intended differentiator is **cross-domain intelligence**: not tracking modules in isolation, but understanding how they interact.

```mermaid
flowchart LR
    TASKS[Tasks] --- CORE((OMNIA<br/>context))
    STUDY[Study] --- CORE
    DEAD[Deadlines / exams] --- CORE
    GOALS[Long-term Goals] --- CORE
    FIT[Fitness] --- CORE
    SLEEP[Sleep] --- CORE
    HAB[Habits] --- CORE
    ACT[Activity] --- CORE
    FOCUS[Focus] --- CORE
    CORE ==> PLAN[Adaptive daily plan]
    CORE ==> REC[Recommendations]
```

Example rules of the vision (**none implemented in the canonical app**):

| Signal | → | Adaptation |
|---|---|---|
| Exam approaching | → | Study gains priority, and the daily plan shifts toward revision |
| Poor sleep | → | Recovery context changes, and workload or training may lighten |
| Missed tasks | → | Plan recalculates priorities |
| Stalled exercise progression | → | Fitness recommendation changes |

The backend's rule-based planner already does simple versions of the first two (exam proximity and short or poor sleep). The canonical frontend doesn't call it yet.

## Related

[[AI Roadmap]] · [[Plan]] · [[Dashboard]] · [[Study]] · [[Fitness and Activity]] · [[Sleep and Recovery]] · [[Achievements and Life Timeline]]
