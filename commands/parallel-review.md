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

Spawn **all** selected agents in **one** message — N `Agent` tool-use blocks in a single response, never in sequential waves. They are independent (cold, read-only, no shared state) and must run concurrently; splitting them across turns serializes the slow ones behind the fast ones and is a defect. Agent definitions live in `agents/` — the harness loads their system prompt and tool restrictions automatically. Each agent is cold — pass content as the user message.

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

Apply **Step 5 — Handle agent failures** (`using-agent-skills`): any selected agent that returned no findings is a coverage gap, not a clean axis — surface it, mark it skipped, and gate the verdict to `INCOMPLETE`.

This is a code review → apply **Track B** (structured synthesis). Deduplicate by `file:line`, then classify each finding's confidence:

- `[CONSENSUS]` — flagged by 2+ agents independently → highest-confidence signal, fix first
- Standard — flagged by one agent
- `[UNIQUE]` — notable finding from one agent, not corroborated → preserve, note lower confidence

**Surface contradictions explicitly.** If two agents recommend different fixes for the same location, state both and adjudicate — prefer whichever has evidence (ran the code, caught a type error) over assertion. Never silently average conflicting recommendations.

Adversarial findings are **blind spots** — what the review agents missed as a whole. Surface them as a separate block after findings.

Sort within each tier: `[CONSENSUS]` first, then standard, then `[UNIQUE]`.

```
PARALLEL REVIEW COMPLETE
────────────────────────────────────────
Phase 1:   tsc PASS | lint PASS | test PASS (N tests)
Agents:    ran [list] | skipped [agent — reason, if any]

FINDINGS
[ERROR][CONSENSUS]   file:line — description  (caught by: agent-a + agent-b)
                       Why: ...
                       Fix: ...
[ERROR]              file:line — description
                       Why: ...
                       Fix: ...
[WARNING][UNIQUE]    file:line — description  (agent-name only — lower confidence)
                       Why: ...
                       Fix: ...
[SUGGESTION]         ...

[BLIND SPOTS]                    ← only if adversarial agent ran
  1. concern — scenario → consequence
  2. ...

SUMMARY
Consensus findings: N  (2+ agents — highest confidence)
Errors:      N  (must fix before merge)
Warnings:    N
Suggestions: N
Skipped:     N  (infra failures — coverage gaps, not clean)
Verdict: READY TO MERGE / BLOCKED — <list blockers> / INCOMPLETE — <axes unverified due to skipped agents>
```
