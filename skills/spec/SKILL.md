---
name: spec
description: Turn a discovery brief or clear ask into a PRD before coding: objective, users, scope, constraints, boundaries, acceptance criteria. Writes the feature's intent file under docs/planning/ so downstream skills execute with intent, not guesses. Adapted from addyosmani/agent-skills spec-driven-development (MIT).
alwaysApply: false
craftkitInject: planning-resolve, external-sources
---

**Model:** everyday. Escalate when the feature is hard to reverse (schema, public API, payment/auth surface) per the karpathy hard-to-reverse gate.

> **Core behaviors:** Surface assumptions. STOP and ask when confused; never invent requirements. Simplicity first (YAGNI on scope). See `/using-agent-skills`.
> **Forward, not backward.** `/spec` defines what *will* be built, and owns `docs/planning/<slug>.md`. `/fe-context` documents what *was* changed, derived from the diff. They no longer share a file: intent is stored per feature, derived context is not stored at all (ADR-0001, ADR-0002).

---

## When to use

Starting a new feature/module/significant change. Best run after `/interview` (feeds it a Discovery Brief) and optionally `/ideate` (feeds it a chosen approach). If the ask is still fuzzy → `/interview` first. If the *approach* is open → `/ideate` first.

## Pre-flight

- No Discovery Brief and the ask is underspecified → `Ask is underspecified. Run /interview first? (y/n)`. Don't guess requirements into a spec.
- Approach genuinely open (multiple viable architectures) → offer `/ideate` before committing the spec.

---

## The PRD: sections

Keep each tight. A spec is a contract, not an essay. Omit a section only if truly N/A (say why).

| Section | Contents |
|---------|----------|
| **Objective** | 1–2 sentences: the user problem and why it's worth solving now. |
| **Users & job** | Who, and the job they hire this for. |
| **Success criteria** | Measurable: how we verify it worked. Each maps to a later acceptance test. |
| **In scope** | Bullets: what this delivers. |
| **Out of scope** | Bullets: explicit non-goals. The most-skipped, highest-value section. |
| **Constraints** | Platform, stack, deadline, existing systems, data, compliance. |
| **Key decisions** | Non-obvious choices + the *why* (link `/adr` for weighty ones). |
| **Risks & open questions** | What could break the plan; anything still unresolved (flagged, not invented). |
| **Acceptance criteria** | Given/when/then or a checklist: the definition of done `/plan` breaks into tasks. |

Every success criterion must be verifiable. If you can't name how it's checked, it's a wish, not a criterion. Push back on unmeasurable goals.

---

## Write the feature's intent file

`/spec` **creates** the feature's intent file and owns its `## Spec` section. Nothing else creates
it; `/plan` and `/adr` fill their own sections in the same file (see the resolution partial above
for the shape and the `status` field).

**Ask the author for the slug.** It is the durable key for this feature, so it is named, never
derived: a branch name breaks on rename and has no answer on `main`. One or three kebab words.

**Ask for the feature's Figma and Lark pointers** (file key + node id, doc token). Record each
under `sources:` with the marker read now per `external-sources`, or `seen: none` when it is
`cannot-verify`. No pointers → omit `sources:`.

Create `docs/planning/` if absent, then write `docs/planning/<slug>.md`:

```markdown
---
slug: {{slug}}
status: active
created: {{ISO date}}
sources:
  - kind: {{figma|lark}}
    ref: {{pointer}}
    seen: {{marker:value, or none}}
---

# {{feature}}

## Spec
**Updated:** {{ISO timestamp}} · **By:** /spec

- **Objective:** …
- **Users & job:** …
- **Success:** …
- **In scope:** …
- **Out of scope:** …
- **Constraints:** …
- **Key decisions:** …
- **Acceptance:** …

## Task Plan
_(owned by /plan)_

## Decisions
_(pointers appended by /adr)_
```

Summarize rather than paste; an intent file past ~200 lines is a spec nobody rereads. If the file
already exists, update `## Spec` only and leave Task Plan and Decisions intact.

**Tell the author to commit it on the feature branch now.** An uncommitted intent file survives
`git checkout` and follows them onto other branches, which is exactly the ambiguity the per-feature
layout exists to remove.

## Output

Print the PRD to the user, then confirm the write:
```
SPEC: <feature>  ·  written to docs/planning/<slug>.md  (status: active)
Verifiable success criteria: <N>   Out-of-scope items: <N>   Open questions: <N>
→ Next: /plan to break this into tasks · optionally /ideate if approach still open.
```

Do not proceed to `/plan` automatically; it is opt-in.
