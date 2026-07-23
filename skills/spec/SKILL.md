---
name: spec
description: Turn a discovery brief or clear ask into a PRD before coding — objective, users, scope, constraints, boundaries, acceptance criteria. Writes a forward-planning block into docs/context.md so downstream skills execute with intent, not guesses. Adapted from addyosmani/agent-skills spec-driven-development (MIT).
alwaysApply: false
---

**Model:** everyday — escalate (`claude-opus-4-8`) when the feature is hard to reverse (schema, public API, payment/auth surface) per the karpathy hard-to-reverse gate.

> **Core behaviors:** Surface assumptions. STOP and ask when confused — never invent requirements. Simplicity first (YAGNI on scope). See `/using-agent-skills`.
> **Forward, not backward.** `/spec` defines what *will* be built. `/fe-context` documents what *was* changed (from the diff). They meet in `docs/context.md` — `/spec` writes the forward block, `/fe-context` preserves it.

---

## When to use

Starting a new feature/module/significant change. Best run after `/interview` (feeds it a Discovery Brief) and optionally `/ideate` (feeds it a chosen approach). If the ask is still fuzzy → `/interview` first. If the *approach* is open → `/ideate` first.

## Pre-flight

- No Discovery Brief and the ask is underspecified → `Ask is underspecified — run /interview first? (y/n)`. Don't guess requirements into a spec.
- Approach genuinely open (multiple viable architectures) → offer `/ideate` before committing the spec.

---

## The PRD — sections

Keep each tight. A spec is a contract, not an essay. Omit a section only if truly N/A (say why).

| Section | Contents |
|---------|----------|
| **Objective** | 1–2 sentences: the user problem and why it's worth solving now. |
| **Users & job** | Who, and the job they hire this for. |
| **Success criteria** | Measurable — how we verify it worked. Each maps to a later acceptance test. |
| **In scope** | Bullets — what this delivers. |
| **Out of scope** | Bullets — explicit non-goals. The most-skipped, highest-value section. |
| **Constraints** | Platform, stack, deadline, existing systems, data, compliance. |
| **Key decisions** | Non-obvious choices + the *why* (link `/adr` for weighty ones). |
| **Risks & open questions** | What could break the plan; anything still unresolved (flagged, not invented). |
| **Acceptance criteria** | Given/when/then or a checklist — the definition of done `/plan` breaks into tasks. |

Every success criterion must be verifiable — if you can't name how it's checked, it's a wish, not a criterion. Push back on unmeasurable goals.

---

## Write the forward-planning block into docs/context.md

`docs/context.md` is the single source of truth all fe-* skills read. `/spec` owns a delimited **PLANNING** block there; `/plan` and `/adr` append into the same block. `/fe-context` preserves it verbatim on regenerate.

Create `docs/context.md` (and `docs/`) if absent — a header-only stub is fine; `/fe-context` fills the backward sections later. Insert/replace this block:

```markdown
<!-- BEGIN PLANNING — managed by /spec /plan /adr; preserved by /fe-context -->
## Planning (forward)
**Updated:** {{ISO timestamp}} · **By:** /spec

### Spec — {{feature}}
- **Objective:** …
- **Users & job:** …
- **Success:** …
- **In scope:** …
- **Out of scope:** …
- **Constraints:** …
- **Key decisions:** …
- **Acceptance:** …

### Task Plan
_(filled by /plan)_

### Decisions
_(appended by /adr)_
<!-- END PLANNING -->
```

Keep the block inside the 600-line budget `/fe-context` enforces — summarize, don't paste. If the block already exists, update the `### Spec` subsection only; leave Plan/Decisions intact.

---

## Output

Print the PRD to the user, then confirm the write:
```
SPEC — <feature>  ·  written to docs/context.md PLANNING block
Verifiable success criteria: <N>   Out-of-scope items: <N>   Open questions: <N>
→ Next: /plan to break this into tasks · optionally /ideate if approach still open.
```

Do not proceed to `/plan` automatically — opt-in.
