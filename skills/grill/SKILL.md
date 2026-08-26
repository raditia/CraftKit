---
name: grill
description: Stress-test an existing plan, decision, or design via a frontier-round interview: map a design tree, ask every currently-askable question per round with a recommended answer, until nothing is silently assumed. Parks ungrillable questions instead of talking them out. Captures resolved terms into docs/glossary.md and offers /adr for hard-to-reverse decisions. Adapted from mattpocock/skills grilling + grill-with-docs (MIT).
alwaysApply: false
---

**Model:** everyday. The value is question selection and tree bookkeeping.

> **Core behaviors:** Surface assumptions. Facts are your job, decisions are the user's. See `/using-agent-skills`.
> **Stress-test, not discovery.** `/grill` interrogates a plan the user already has. No plan yet → `/interview` (de-fuzz) or `/ideate` (options). Cold single-pass roast of a plan doc → `plan-roaster` agent. Interactive rounds are the point here.

---

## When to use

User has a plan, decision, or design and wants it challenged before committing. Triggers: "grill me/this", "stress-test my plan", "poke holes in this", "challenge this design".

---

## Method: design tree, frontier rounds

1. **Map the plan as a design tree.** Every decision branches into the decisions that hang off it.
2. **The frontier** is every decision whose prerequisites are already settled: questions askable *now* without guessing at answers not yet heard. Ask the whole frontier in one round, numbered.
3. **Format each question** so the whole round is answerable by number alone (`1 yes, 2 the second option, 3 no because...`):

   ```
   ❓ **Q1. <question title>**
   <question body, with choices where useful>

   ➡️ <your recommended answer>
   ```

   Word the recommendation so that agreeing with it never means answering "no" to the question above it. Where the honest recommendation contradicts the question's framing, rewrite the question.
4. **Recompute after each round.** Settled decisions push the frontier outward and unblock dependent questions. A question whose answer depends on another question still open *this* round belongs to a later round.
5. **Facts are your job, never the user's.** A frontier question needing a fact from the environment (code, configs, docs) → dispatch a sub-agent (`Explore`) to find it. Don't block: only questions downstream of the lookup wait, so ask the rest of the frontier now. Decisions go to the user; lookups never do.
6. **The frontier is your judgement, not a computed graph.** Two questions in one round can turn out to be coupled, one answer changing the other. When the user says so, reopen that branch next round and name which answers you are re-asking. Defending the round is the failure.
7. **Done when the frontier is empty**, every branch visited, nothing silently assumed. Do not act on the plan until the user confirms shared understanding.

---

## Ungrillable questions

Some questions cannot be settled by talking: how a layout should look, how an interaction should feel, one long form versus three pages. They need something to react to. Name them ungrillable, park them, and keep grilling the rest of the frontier.

Route each parked one: option space still open → `/ideate`; needs a working thing to look at → a throwaway build, then one line back here. Talking through an ungrillable question is where sessions balloon, because you rephrase, the user guesses, and scope grows to fill the uncertainty.

---

## Session health

- **Challenge blanket agreement.** A user who answers "agreed" to every question in a round has decided nothing, and the plan that comes out carries certainty it has not earned. On an all-agreed round, pick the load-bearing answer and push once: "you agreed to X, which rules out Y. Intended?"
- **Split instead of grinding.** A frontier past roughly a dozen questions, or a round count that keeps climbing, means the scope is too big. Stop and propose splitting the plan, then grill each piece in its own session. Long sessions degrade on their own: a full context window produces worse questions.
- **One at a time on request.** User prefers sequential? Same design tree, same frontier, one question per round. This is supported, not merely tolerated.

---

## Docs as you go

- **Glossary.** When a fuzzy term gets a precise canonical meaning, update `docs/glossary.md` at that moment, never batched. One line per term: `- **Term**: definition.` Glossary holds language only, zero implementation detail. If the user's usage conflicts with an existing entry, challenge immediately: "glossary defines *cancellation* as X, you seem to mean Y. Which?"
- **ADRs.** When a settled decision is (a) hard to reverse, (b) surprising without context, AND (c) a real tradeoff, offer `/adr`. All three or skip.

Note: `docs/glossary.md` is a standalone file, not part of `docs/context.md`, which `/fe-context` regenerates.

---

## Output

End of session, one block: rounds run, decisions settled, glossary terms added, ADRs recorded, open risks the user explicitly accepted.
