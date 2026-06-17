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
3. Read `docs/context.md` (Summary + Key Changes only) if present

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

Spawn selected agents simultaneously in a single response using the Agent tool. Use `caveman:cavecrew-reviewer` subagent type. Set `model` based on the skill's `**Model:**` tier: `cheapest` → `"haiku"`, `everyday` → `"sonnet"`, `escalated` → `"opus"`. Each agent is cold — pass the full diff and context.md summary inline.

**Agent: code-quality (5-axis)**

```
Review this diff for correctness, readability, architecture (EVPMR), security, and performance.
[Add if security-sensitive: Pay extra attention to the security axis — auth/payment code present.]
[Add if package.json changed: Audit any new dependencies for bundle impact, maintenance status, and known vulnerabilities.]

DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>

Output: [SEVERITY] file:line — description / Why: ... / Fix: ...
Severity: [ERROR]=blocks merge [WARNING]=should fix [SUGGESTION]=optional
End with: REVIEW SUMMARY / Errors: N / Warnings: N / Suggestions: N
```

**Agent: fe-review (EVPMR checklist)**

```
Run the EVPMR checklist on this diff:
- View: no useState/useEffect/API calls, calls usePresenter*(), pure JSX
- Presenter: no JSX, returns plain object
- Model: no React imports, no side effects
- Entry: wraps in <ErrorBoundary> from react-error-boundary
- Resource: all display strings here, none hardcoded in View
- Styling: StyleSheet.create() + Token.spacing.* / Token.color.* / Token.border.* only, no inline styles
- TypeScript: no any, discriminated unions for async data, explicit return types
- React correctness: derive don't sync, ternary not && for conditional render, stable keys, functional setState
- Tracking: useTracker() in Presenter handlers, not in View

DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>

Output: [SEVERITY] file:line — description / Why: ... / Fix: ...
End with: EVPMR SUMMARY / Errors: N / Warnings: N / Suggestions: N
```

**Agent: fe-a11y** _(only if View*.tsx changed)_

```
Review this diff for accessibility issues in React Native / Next.js:
Check accessible labels, roles, focus management, dynamic announcements, reduced motion, touch target sizes, color contrast reliance.

DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>

Output: [SEVERITY] file:line — description / Why: ... / Fix: ...
End with: A11Y SUMMARY / Errors: N / Warnings: N / Suggestions: N
```

**Agent: adversarial** _(only if 3+ EVPMR layers changed)_

```
You are a devil's advocate reviewer. Your job: argue the strongest case AGAINST merging this diff. Find risks, hidden assumptions, design smells, missing edge cases, or reasons this change could cause production issues. Be specific — vague concerns don't count.

DIFF:
<full diff>

CONTEXT:
<docs/context.md Summary + Key Changes>

Output: list of specific concerns, most severe first. No praise.
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
