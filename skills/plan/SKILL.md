---
name: plan
description: Decompose a spec into small, verifiable, dependency-ordered tasks — each with an acceptance check and the skill that executes it. Writes the task plan into the docs/context.md PLANNING block. Offers a plan-roaster stress-test before build. Adapted from addyosmani/agent-skills planning-and-task-breakdown (MIT).
alwaysApply: false
---

**Model:** everyday — escalate (`claude-opus-4-8`) when the dependency graph is large or tasks touch > 5 interdependent files.

> **Core behaviors:** Goal-driven — every task gets a verifiable check. Surface assumptions. Simplicity first — don't invent tasks the spec doesn't need. See `/using-agent-skills`.
> **Breakdown, not critique.** `/plan` produces the task list. The `plan-roaster` agent attacks it. Run roaster *after* planning, before build.

---

## When to use

You have a `/spec` (or an equivalently clear ask) and need implementable units. No spec yet → run `/spec` first; the plan is only as good as the spec behind it.

## Method

1. **Read the spec** — from the `docs/context.md` PLANNING block, or inline.
2. **Derive tasks from acceptance criteria** — each criterion becomes one or more tasks. A task with no acceptance check is not a task; either give it one or drop it.
3. **Size to verifiable units** — each task is small enough to build + verify in one pass. If a task can't state its own done-check, split it.
4. **Order by dependency** — a task lists what must land first. Mark tasks with no unmet dependency as parallelizable.
5. **Route each task** — name the skill/command that executes it (`/fe-scaffold`, `/fe-test`, `/android-scaffold`, …). Planning that doesn't say *who executes* is a wish list.

## Task shape

| Field | Contents |
|-------|----------|
| **ID** | T1, T2, … (stable — referenced by deps) |
| **Task** | Imperative, one line. |
| **Acceptance** | The check that proves it's done (test passes, tsc clean, renders X). |
| **Depends on** | Task IDs, or `—`. |
| **Executes via** | Skill/command that does the work. |

---

## Output — write into docs/context.md, then print

Update the `### Task Plan` subsection of the PLANNING block (see `/spec` for the block format; leave Spec/Decisions intact):

```markdown
### Task Plan
**Updated:** {{ISO timestamp}} · **By:** /plan

| ID | Task | Acceptance | Depends on | Executes via |
|----|------|-----------|-----------|--------------|
| T1 | … | … | — | /fe-scaffold |
| T2 | … | … | T1 | /fe-test |

**Parallelizable now:** T1, T3
**Critical path:** T1 → T2 → T5
```

Print the same table to the user, then:
```
PLAN — <feature>  ·  <N> tasks, critical path <M> deep, <K> parallelizable
→ Stress-test before building? Spawn plan-roaster (Agent: subagent_type "plan-roaster") on this plan. (recommended for hard-to-reverse work)
→ Then: /parallel-build to execute.
```

Offer `plan-roaster` — don't auto-run it. If the user accepts, pass the task table as the agent prompt and fold its weakest-assumption finding back into the plan before build.
