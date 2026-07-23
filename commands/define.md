---
name: define
description: Checkpoint-gated pre-build planning pipeline — chains /interview → /spec → /plan (offering /ideate and plan-roaster where useful) so an underspecified feature ask becomes a reviewed spec + task plan in one invocation. Pauses for your approval between phases. Writes the forward-planning block into docs/context.md. Use before building a feature whose scope, approach, or tasks aren't yet clear.
---

**Model:** everyday — escalate the spec phase (`claude-opus-4-8`) for hard-to-reverse features (schema, public API, payment/auth).

> Triggered by: "plan this feature", "define feature X", "help me spec and plan X", "let's plan before building", `/define`
> **Pre-build only.** `/define` stops at a reviewed plan and hands to `/parallel-build`. It does **not** build, and it does **not** write adr/docs — those are post-build (offered by `/parallel-ship`).

---

## How this runs — checkpoint-gated

Each phase runs the underlying skill, prints its output, then **stops at a gate**. Do not proceed until the user approves. This is the point of the command: a bad spec compounds into bad tasks, so the user corrects between phases, not after.

At every gate emit exactly:
```
CHECKPOINT — <phase> done.
<one-line summary of what was produced>
→ (c)ontinue to <next phase> · (e)dit this phase · (s)top here
```
`edit` → apply the user's changes to the current phase output, re-gate. `stop` → end, leave artifacts as-is. Only `continue` advances.

Platform is irrelevant to planning — `/interview` `/spec` `/plan` are platform-agnostic. Platform matters only at the **Executes via** column of the plan (route tasks to `/fe-scaffold` vs `/android-scaffold` vs `/ios-scaffold`) and at build time.

---

## Phase 1 — Discover (`/interview`)

Run `/interview`. Skip only if the ask is already at ~95% confidence (say so and jump to Phase 2).

**Gate:** Discovery Brief produced, or user says the ask is clear enough.

## Phase 1.5 — Widen approach (`/ideate`, optional)

If the *approach* is genuinely open (multiple viable architectures), offer `/ideate` — do not auto-run (it costs 5–10× a direct answer; its own gate applies). If the user declines or the approach is obvious, skip silently.

**Gate:** none — optional side-quest. Feed any chosen shortlist into Phase 2 as the design decision.

## Phase 2 — Spec (`/spec`)

Run `/spec` using the Discovery Brief (+ any `/ideate` choice) as input. Writes the `### Spec` subsection of the `docs/context.md` PLANNING block.

**Gate:** PRD printed, every success criterion verifiable, out-of-scope non-empty. Written to `docs/context.md`.

## Phase 3 — Plan (`/plan`)

Run `/plan` against the spec. Writes the `### Task Plan` subsection. Route each task's **Executes via** to the platform's scaffold/test skill.

**Gate:** task table printed with acceptance check + deps + executing skill per task; written to `docs/context.md`.

## Phase 3.5 — Stress-test (`plan-roaster`, offered)

Offer to spawn the `plan-roaster` agent (`subagent_type: "plan-roaster"`, pass the task table). Recommended for hard-to-reverse work. Fold its weakest-assumption finding back into the plan before handing off. Skip on user decline.

---

## Done

```
DEFINE COMPLETE
──────────────────────────────
Discovery:  <confidence>%  (or "ask was clear — skipped")
Spec:       docs/context.md — <N> verifiable criteria, <M> out-of-scope
Plan:       <T> tasks · critical path <D> deep · <P> parallelizable
Roaster:    <score>/10  (or "skipped")
→ Next: /parallel-build to execute · adr/docs offered at /parallel-ship
```

Do not start building — `/parallel-build` is a separate opt-in step.
