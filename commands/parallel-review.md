---
name: parallel-review
description: Dynamic parallel code review — classifier reads the diff, selects only relevant agents, spawns them concurrently. Adapts to what actually changed.
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk lint`, `rtk test`
**Model:** everyday — escalate for security-sensitive changes or major arch tradeoffs

> Triggered by: "parallel review", "fast review", "review in parallel", "review fast", `/parallel-review`

---

## Phase 0 — Context

1. Detect base: `rtk git remote show origin | grep 'HEAD branch'`
2. `rtk git diff <base>...HEAD --name-only` + `rtk git diff <base>...HEAD`
3. Apply standard context loading (`using-agent-skills`) — freshness check (branch + commit), regenerate if stale or missing, read Summary + Key Changes

---

## Phase 1 — Fast gates (all three in parallel)

Run simultaneously as parallel Bash calls:

```bash
rtk tsc --noEmit
```
```bash
rtk lint <changed-files>
```
```bash
rtk test --testPathPattern="<feature-path>" --no-coverage
```

**Gate:** All three must pass. If any fail → report immediately, skip Phase 2.

```
PHASE 1
tsc:   PASS / FAIL
lint:  PASS / FAIL
test:  PASS / FAIL (N tests)
→ Proceeding to classification / BLOCKED — fix above first
```

---

## Phase 1.5 — Classify

Apply the parallel workflow classifier from `using-agent-skills`. Announce selected agents before proceeding.

---

## Phase 2 — Dynamic parallel agents

Spawn selected agents simultaneously in a single response using the Agent tool. Agent definitions live in `agents/` — the harness loads their system prompt and tool restrictions automatically. Each agent is cold — pass content as the user message.

**Agent: code-quality** (`subagent_type: "code-quality"`)

Pass as user message:
```
[if auth/payment/credential paths changed, prepend: "Security-sensitive code present — emphasize security axis."]
[if package.json changed, prepend: "package.json changed — audit new dependencies for bundle impact, maintenance status, and known vulnerabilities."]

DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>
```

**Agent: fe-review** (`subagent_type: "fe-review"`)

Pass as user message:
```
DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>
```

**Agent: fe-a11y** (`subagent_type: "fe-a11y"`) — _only if View*.tsx changed_

Pass as user message:
```
DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>
```

**Agent: adversarial** (`subagent_type: "adversarial"`) — _only if 3+ EVPMR layers changed_

Pass as user message:
```
DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>
```

---

## Phase 3 — Synthesize

Merge findings from all agents. Deduplicate: same `file:line` flagged by multiple agents → keep once, note which axes caught it. Sort: `[ERROR]` → `[WARNING]` → `[SUGGESTION]`. Adversarial concerns appear as a separate block at the end.

```
PARALLEL REVIEW COMPLETE
────────────────────────────────────────
Phase 1:   tsc PASS | lint PASS | test PASS (N tests)
Agents:    [list of agents that ran]

FINDINGS
[ERROR]      file:line — description
               Why: ...
               Fix: ...
[WARNING]    ...
[SUGGESTION] ...

[ADVERSARIAL CONCERNS]          ← only if adversarial agent ran
  ...

SUMMARY
Errors:      N  (must fix before merge)
Warnings:    N
Suggestions: N
Verdict: READY TO MERGE / BLOCKED — <list blockers>
```
