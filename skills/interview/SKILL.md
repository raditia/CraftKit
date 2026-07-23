---
name: interview
description: One-question-at-a-time discovery to de-fuzz an underspecified feature ask before spec/build. Asks the single highest-information question each turn until requirements reach ~95% confidence, then hands off to /spec. Adapted from addyosmani/agent-skills (MIT).
alwaysApply: false
---

**Model:** everyday — the value is question selection, not raw generation.

> **Core behaviors:** Surface assumptions. STOP and ask when confused. Never invent requirements. See `/using-agent-skills`.
> **Discovery, not design.** `/interview` extracts *what the user wants* — it does not propose solutions (that's `/ideate`) or write the spec (that's `/spec`). Hand off when confident.

---

## When to use

The ask is underspecified and guessing is expensive: a new feature/screen/module with unstated scope, users, constraints, or success criteria. If the ask is already clear, skip — go straight to `/spec` or `/parallel-build`.

Do **not** use for: known bugs (`/debug`), option generation (`/ideate`), or lookups.

---

## Method — single-question loop

1. **Track confidence.** Estimate 0–100% how well you could write the spec right now. Start low for a vague ask.
2. **Ask ONE question** — the single highest-information-gain question that most reduces uncertainty. Never batch. Batching lets the user skim and answer shallowly; one question forces a real answer.
3. **Prefer concrete over open.** Offer 2–4 candidate answers when you can (use `AskUserQuestion`) — recognition beats recall. Fall back to open text only when the space is genuinely unbounded.
4. **Update confidence**, restate the delta in one line (`Now know: X. Still fuzzy: Y.`), repeat.
5. **Stop at ~95%** or when the user says "enough" — do not over-interview. Diminishing returns is a real cost.

### Question priority — ask in this order of leverage

| Rank | Dimension | Why it's high-leverage |
|------|-----------|------------------------|
| 1 | **Users & job** | Who uses this and what job are they hiring it for? Wrong user → wrong everything. |
| 2 | **Success criteria** | How do we know it worked? Unmeasurable goal → unverifiable build. |
| 3 | **Scope boundary** | What is explicitly *out*? Undrawn boundary → scope creep. |
| 4 | **Constraints** | Platform, deadline, existing systems, data, compliance. |
| 5 | **Edge cases & failure** | Empty/error/offline/permission-denied states. |
| 6 | **Non-goals & tradeoffs** | What are we willing to sacrifice (speed vs polish, etc.)? |

Skip a rank if the ask already answers it — spend questions only on unknowns.

---

## Output — Discovery Brief

When confidence ≥ 95% (or user stops), emit and stop:

```
DISCOVERY — <feature, one line>
Confidence: <N>%

USERS & JOB      <who · what job>
SUCCESS          <measurable criteria>
IN SCOPE         <bullets>
OUT OF SCOPE     <bullets — explicit non-goals>
CONSTRAINTS      <platform / deadline / systems / data>
EDGE CASES       <states that must be handled>
OPEN QUESTIONS   <anything still <95% — flagged, not invented>

→ Next: /spec to turn this into a PRD.
```

Offer to persist the brief into `docs/context.md` (see `/spec` for the forward-planning block). Do not write it silently — ask.
