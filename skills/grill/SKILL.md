---
name: grill
description: Stress-test an existing plan, decision, or design via a frontier-round interview — map a design tree, ask every currently-askable question per round with a recommended answer, until nothing is silently assumed. Captures resolved terms into docs/glossary.md and offers /adr for hard-to-reverse decisions. Adapted from mattpocock/skills grilling + grill-with-docs (MIT).
alwaysApply: false
---

**Model:** everyday — the value is question selection and tree bookkeeping.

> **Core behaviors:** Surface assumptions. Facts are your job, decisions are the user's. See `/using-agent-skills`.
> **Stress-test, not discovery.** `/grill` interrogates a plan the user already has. No plan yet → `/interview` (de-fuzz) or `/ideate` (options). Cold single-pass roast of a plan doc → `plan-roaster` agent. Interactive rounds are the point here.

---

## When to use

User has a plan, decision, or design and wants it challenged before committing. Triggers: "grill me/this", "stress-test my plan", "poke holes in this", "challenge this design".

---

## Method — design tree, frontier rounds

1. **Map the plan as a design tree** — every decision branches into the decisions that hang off it.
2. **The frontier** = every decision whose prerequisites are already settled — questions askable *now* without guessing at answers not yet heard. Ask the whole frontier in one round, numbered.
3. **Format each question:**

   ```
   ❓ **Q1 — <question title>**: <question body, with choices where useful>

   ➡️ <your recommended answer>
   ```

4. **Recompute after each round.** Settled decisions push the frontier outward and unblock dependent questions. A question whose answer depends on another question still open *this* round belongs to a later round.
5. **Facts are your job, never the user's.** A frontier question needing a fact from the environment (code, configs, docs) → dispatch a sub-agent (`Explore`) to find it. Don't block: only questions downstream of the lookup wait — ask the rest of the frontier now. Decisions go to the user; lookups never do.
6. **Done when the frontier is empty** — every branch visited, nothing silently assumed. Do not act on the plan until the user confirms shared understanding.

---

## Docs as you go

- **Glossary** — when a fuzzy term gets a precise canonical meaning, update `docs/glossary.md` at that moment — never batch. One line per term: `- **Term** — definition.` Glossary holds language only, zero implementation detail. If the user's usage conflicts with an existing entry, challenge immediately: "glossary defines *cancellation* as X, you seem to mean Y — which?"
- **ADRs** — when a settled decision is (a) hard to reverse, (b) surprising without context, AND (c) a real tradeoff, offer `/adr`. All three or skip.

Note: `docs/glossary.md` is a standalone file — not part of `docs/context.md`, which `/fe-context` regenerates.

---

## Output

End of session, one block: rounds run, decisions settled, glossary terms added, ADRs recorded, open risks the user explicitly accepted.
