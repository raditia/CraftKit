---
name: parallel-build
description: Dynamic parallel build workflow — sequential context + scaffold + implement, then classifier-selected validation agents run concurrently. Adapts to what was built.
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk lint`, `rtk test`
**Model:** everyday — escalate for architectural decisions with non-obvious tradeoffs

> Triggered by: "parallel build", "build in parallel", "build fast", `/parallel-build`

---

## Phase 0 — Context (sequential)

Run the `/fe-context` workflow:
1. Detect base: `rtk git remote show origin | grep 'HEAD branch'`
2. `rtk git log --oneline <base>...HEAD` + `rtk git diff <base>...HEAD`
3. Write `docs/context.md` (≤ 600 lines): Summary, Architecture Patterns in Use, Key Changes, Test Coverage Needed

**Gate:** `docs/context.md` exists and covers the feature scope.

---

## Phase 1 — Scaffold (sequential)

Follow the `/fe-scaffold` workflow — surface assumptions first, create the 5-file EVPMR module.

**Gate:** All 5 files created, `rtk tsc --noEmit` passes.

---

## Phase 2 — Implement (sequential)

Build the feature. Apply `/fe-patterns` and `/fe-performance` continuously as you build — not as a post-pass. `fe-rules` (always active) enforces layer constraints throughout.

**Gate:** `rtk tsc --noEmit` passes after every logical chunk.

---

## Phase 3 — Fast gates (parallel)

Run simultaneously as parallel Bash calls:

```bash
rtk tsc --noEmit
```
```bash
rtk lint <changed-files>
```

**Gate:** Both must pass. If any fail → fix before Phase 4.

```
PHASE 3
tsc:   PASS / FAIL
lint:  PASS / FAIL
→ Proceeding to classification / BLOCKED — fix above first
```

---

## Phase 4 — Classify what was built

Apply the parallel workflow classifier from `using-agent-skills`, but scan the **newly created/modified files** (not just the diff) — read their actual content to determine which layers exist and what they do.

Additional build-specific rules:

| What was built | Add to agent set |
|----------------|-----------------|
| View with form inputs or interactive elements | `fe-a11y` |
| Presenter with data fetching or complex state | `fe-performance` |
| New component used in navigation | `fe-a11y` |
| Large module (> 5 files or > 300 lines total) | adversarial agent |

Announce selected agents before proceeding.

---

## Phase 5 — Dynamic parallel validation agents

Spawn **all** selected agents in **one** message — N `Agent` tool-use blocks in a single response, never in sequential waves. They are independent (cold, read-only, no shared state) and must run concurrently; splitting them across turns serializes the slow ones behind the fast ones and is a defect. Agent definitions live in `agents/` — the harness loads their system prompt and tool restrictions automatically. Each agent is cold — pass content as the user message. Pass full file contents, not just the diff — agents need the full implementation context.

**Agent: fe-review** (`subagent_type: "fe-review"`)

Pass as user message:
```
FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>
```

**Agent: fe-patterns** (`subagent_type: "fe-patterns"`)

Pass as user message:
```
FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>
```

**Agent: fe-a11y** (`subagent_type: "fe-a11y"`) — _only if interactive View components built_

Pass as user message:
```
FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>
```

**Agent: fe-performance** (`subagent_type: "fe-performance"`) — _only if Presenter with data fetching or complex state_

Pass as user message:
```
FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>
```

**Agent: adversarial** (`subagent_type: "adversarial"`) — _only if large module built (> 5 files or > 300 lines total)_

Pass as user message:
```
This is a newly built feature — argue the strongest case against shipping it as-is.

FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>
```

**Synthesize Phase 5 findings** — apply **Track B** (structured synthesis):
- `[CONSENSUS]` — flagged by 2+ agents independently → fix before proceeding
- Standard — flagged by one agent
- `[UNIQUE]` — notable finding from one agent only → preserve, note lower confidence
- Adversarial findings → **blind spots** block (what review agents missed as a whole)

**Gate (Phase 5):** No `[ERROR]` findings (consensus or single-agent) remain before proceeding to tests.

---

## Phase 6 — Tests (sequential)

Run the `/fe-test` workflow — write tests covering all new code paths. Coverage ≥ 93% on Lines, Branches, Functions, Statements.

**Gate:** All tests pass. Coverage ≥ 93% on all four metrics.

---

## Done

```
PARALLEL BUILD COMPLETE
────────────────────────────────────────
Files created:   [list all 5 EVPMR files]
Phase 3:         tsc PASS | lint PASS
Agents (Phase 5): [list of agents that ran]

FINDINGS (from validation)
[ERROR][CONSENSUS]   file:line — description  (caught by: agent-a + agent-b)
[ERROR]              file:line — description
[WARNING][UNIQUE]    file:line — description  (agent-name only — lower confidence)
[SUGGESTION]         ...

[BLIND SPOTS]                    ← only if adversarial agent ran
  1. concern — scenario → consequence

Tests:     PASS (N tests, N new)
Coverage:  Lines N% / Branches N% / Functions N% / Statements N%
Verdict:   DONE / BLOCKED — <list blockers>
```
