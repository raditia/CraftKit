---
name: parallel-ship
description: Dynamic parallel pre-merge check — Phase 1 (tsc + lint + test with coverage gate) then classifier-selected agents run concurrently. Adapts to what actually changed.
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk lint`, `rtk test`
**Model:** everyday — escalate for security-sensitive changes or major arch tradeoffs

> Triggered by: "parallel ship", "fast ship", "ship in parallel", "ship fast", `/parallel-ship`

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
rtk test --testPathPattern="<feature-path>" --coverage
```

Coverage gate: Lines, Branches, Functions, Statements all ≥ 93%.

**Gate:** All three must pass and coverage must meet threshold. If any fail → report immediately, skip Phase 2.

```
PHASE 1
tsc:      PASS / FAIL
lint:     PASS / FAIL
test:     PASS / FAIL (N tests)
coverage: Lines N% / Branches N% / Functions N% / Statements N% — PASS / FAIL
→ Proceeding to classification / BLOCKED — fix above first
```

---

## Phase 1.5 — Classify

Apply the parallel workflow classifier from `using-agent-skills`. Announce selected agents before proceeding.

---

## Phase 2 — Dynamic parallel agents

Spawn **all** selected agents in **one** message — N `Agent` tool-use blocks in a single response, never in sequential waves. They are independent (cold, read-only, no shared state) and must run concurrently; splitting them across turns serializes the slow ones behind the fast ones and is a defect. Agent definitions live in `agents/` — the harness loads their system prompt and tool restrictions automatically. Each agent is cold — pass content as the user message.

**Do not wait by polling.** Never `grep`/`sleep`-loop over task output files (`tasks/*.output`) to detect completion — the harness wakes the main thread automatically when every spawned agent comes to rest, and re-invokes you with their results. Spin-loops keep running for minutes after the agents already finished. On wake, read the returned results and go straight to Phase 3.

**Agent: code-quality** (`subagent_type: "code-quality"`)

Pass as user message:
```
This is a pre-merge check — be thorough.
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

**Agent: fe-performance** (`subagent_type: "fe-performance"`) — _only if View*.tsx or Presenter*.ts changed_

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

Apply **Step 5 — Handle agent failures** (`using-agent-skills`): any selected agent that returned no findings is a coverage gap, not a clean axis — surface it, mark it skipped, and gate the verdict to `INCOMPLETE` (never `READY TO MERGE` with an infra-skipped review agent).

This is a pre-merge code review → apply **Track B** (structured synthesis). Deduplicate by `file:line`, then classify each finding's confidence:

- `[CONSENSUS]` — flagged by 2+ agents independently → highest-confidence signal, fix first
- Standard — flagged by one agent
- `[UNIQUE]` — notable finding from one agent, not corroborated → preserve, note lower confidence

**Surface contradictions explicitly.** If two agents recommend different fixes for the same location, state both and adjudicate — prefer whichever has evidence over assertion. Never silently average conflicting recommendations.

Adversarial findings are **blind spots** — what all review agents missed. Surface them as a separate block.

Sort within each tier: `[CONSENSUS]` first, then standard, then `[UNIQUE]`.

```
PARALLEL SHIP COMPLETE
────────────────────────────────────────
Phase 1:   tsc PASS | lint PASS | test PASS (N tests)
           Coverage: Lines N% / Branches N% / Functions N% / Statements N%
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

---

## Phase 4 — Document (opt-in, only if verdict READY TO MERGE)

Code is final at this point — the natural moment to capture the *why* and explain the *what*. Offer, never auto-run:

```
→ Before merge, capture documentation? (both optional)
  (a) /adr  — record any architectural decision made on this branch (the why)
  (d) /docs — write engineer + stakeholder documentation for this feature
  (n) skip
```

- **`/adr`** — if the branch made a non-obvious, hard-to-reverse decision, run `/adr` to record it and link it into the `docs/context.md` PLANNING block. One ADR per decision; skip for reversible/local choices.
- **`/docs`** — run `/docs` to produce the dual-audience pair (technical + stakeholder), humanized. Pulls from the PLANNING block + ADRs + the diff.

Skip entirely if the user declines or the change is trivial. Do not block merge on documentation.
