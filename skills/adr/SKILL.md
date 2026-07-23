---
name: adr
description: Record one architectural decision as an immutable ADR — context, options weighed, decision, consequences. Captures the WHY a choice was made so future readers don't re-litigate it. Appends a summary to the docs/context.md PLANNING block. Adapted from addyosmani/agent-skills documentation-and-adrs (MIT).
alwaysApply: false
---

**Model:** everyday.

> **Core behaviors:** Document the *why*, not the what. Surface the tradeoff honestly — record the rejected options and why. See `/using-agent-skills`.
> **Record, not decide.** `/adr` writes down a decision already made (often via `/ideate` or the fusion panel). Deciding is upstream; this captures it so it survives.

---

## When to use

A choice was made that (a) is hard to reverse, (b) shaped the design, or (c) a future engineer will otherwise ask "why on earth is it like this?". One decision per ADR — atomic and immutable. Superseding a past decision = a *new* ADR that references the old one, never an edit.

Skip for reversible, obvious, or local choices — an ADR for everything is noise.

---

## The ADR — one file per decision

Write to `docs/adr/NNNN-<kebab-title>.md` (zero-padded sequence). Create `docs/adr/` if absent.

```markdown
# ADR-NNNN: <short decision title>

- **Status:** Accepted   <!-- Proposed | Accepted | Superseded by ADR-XXXX -->
- **Date:** {{ISO date}}
- **Deciders:** <who>

## Context
What forces the decision — the problem, constraints, and pressures. Neutral; no solution yet.

## Options considered
| Option | Pros | Cons |
|--------|------|------|
| A (chosen) | … | … |
| B | … | … |

## Decision
The option chosen, stated plainly, and the *why* — which force in Context it satisfies that the others don't.

## Consequences
What becomes easier, what becomes harder, and what this locks in. Include the cost, not just the upside.
```

Status honesty: only `Accepted` if truly decided. A decision still being weighed is `Proposed` — don't backfill certainty.

---

## Link into docs/context.md

Append a one-line pointer to the `### Decisions` subsection of the PLANNING block (see `/spec` for the block; leave Spec/Task-Plan intact):

```markdown
### Decisions
- [ADR-0001](adr/0001-<title>.md) — <one-line what & why> — Accepted {{date}}
```

Keep it to the pointer line — the full reasoning lives in the ADR file, not the context block (budget).

## Output

```
ADR-NNNN — <title>  ·  docs/adr/NNNN-<title>.md  ·  linked in docs/context.md
Status: <status>   Options weighed: <N>
```
