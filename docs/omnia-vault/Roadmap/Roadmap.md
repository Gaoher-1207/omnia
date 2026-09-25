---
type: roadmap
---

# Roadmap

Intended order with dependencies. **No dates** are set. Sources: `Shehwaar/README.md` roadmap plus the dependency analysis in this vault.

## Completed checkpoints

| Checkpoint | Commit | What it delivered |
|---|---|---|
| Long-term Goals | `d1e908a` | Measurable and completion-only goals, form, Home preview, tests |
| API infrastructure | `10e8ad2` | `ApiClient`, `ApiConfig`, `ApiException`, JSON helpers, `TokenStore`, Android network config, client tests |
| Authentication and sessions | `70864a7` | `AuthController`, auth screen, Settings account, `UserSession`, fake auth backend tests |
| Frontend documentation | `527020e` | `Shehwaar/README.md` rewrite |

These were built on the Tasks, Focus, onboarding and design work in the canonical frontend that came before them. See [[Git Checkpoints]].

## Dependency graph

```mermaid
flowchart TD
    classDef done fill:#b7e4c7,stroke:#1b4332,color:#000
    classDef next fill:#ffd166,stroke:#7a5c00,color:#000
    classDef later fill:#e9ecef,stroke:#555,color:#000
    classDef vision fill:#e0d4fd,stroke:#5a3fa0,color:#000

    G["Long-term Goals (local)"]:::done
    INF["API infrastructure"]:::done
    AUTH["Auth + sessions"]:::done
    DOC["README / docs"]:::done
    T["Phase 3: Tasks API"]:::next
    DASH["Dashboard + daily targets"]:::later
    PLAN["Daily plan (AI API)"]:::later
    STUDY["Study integration<br/>(model alignment)"]:::later
    TRACK["Activity / Sleep logging"]:::later
    INS["Insights / Progress"]:::later
    GB["Long-term Goals backend<br/>(new module)"]:::later
    AL["Adaptive learning"]:::vision
    FIT["Workout progression"]:::vision
    AIA["AI assistant"]:::vision
    XD["Cross-domain recommendations"]:::vision
    ACH["Achievements + Life Timeline"]:::vision

    INF --> AUTH --> T
    T --> DASH
    DASH --> PLAN
    T --> PLAN
    STUDY --> PLAN
    DASH --> TRACK
    TRACK --> INS
    T --> INS
    STUDY --> INS
    AUTH --> GB
    G --> GB
    STUDY --> AL
    TRACK --> FIT
    PLAN --> AIA
    AL --> XD
    FIT --> XD
    GB --> XD
    AIA --> XD
    GB --> ACH
    FIT --> ACH
    AL --> ACH
```

Green = done · Yellow = next · Grey = integration phases · Purple = product vision.

## Sequence

1. **[[Phase 3 - Tasks API Integration]]** (next)
2. **Dashboard and [[Daily Targets]]**: `/dashboard` on Home and Track, plus a targets editor in Settings
3. **Daily plan**: replace `samplePlan` with `/ai/daily-plan`
4. **Study integration**, then the [[Adaptive Learning Roadmap]]
5. **Activity and sleep** logging, then the [[Fitness Roadmap]]
6. **Insights and progress** from real data
7. **Long-term Goals backend**. This is independent of 2–6 and can be scheduled whenever needed.
8. **[[AI Assistant]]**, then cross-domain recommendations ([[AI Roadmap]])
9. **[[Achievements and Life Timeline]]**

Details per integration phase: [[Backend Integration Roadmap]].

Up: [[00 - OMNIA|OMNIA]] · status today: [[Current Status]]
