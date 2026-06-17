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

Spawn selected agents simultaneously in a single response using the Agent tool. Use `caveman:cavecrew-reviewer` subagent type. Set `model` based on the skill's `**Model:**` tier: `cheapest` → `"haiku"`, `everyday` → `"sonnet"`, `escalated` → `"opus"`. Each agent is cold — pass the full new file contents and context.md summary inline (not just the diff — agents need the full implementation context).

**Agent: fe-review (EVPMR checklist)**

```
Review this newly built EVPMR feature module for pattern violations:
- View: no useState/useEffect/API calls, calls usePresenter*(), pure JSX, JSX ≤ 80 lines or extracted sub-components
- Presenter: no JSX, returns plain object, hook ≤ 100 lines or split
- Model: no React imports, no side effects, async data as discriminated unions
- Entry: wraps in <ErrorBoundary> from react-error-boundary
- Resource: all display strings here, none hardcoded in View
- Styling: StyleSheet.create() + Token.spacing.* / Token.color.* / Token.border.* only
- TypeScript: no any, explicit return types on exported functions
- React correctness: derive don't sync, ternary not && for conditional render, stable keys
- Tracking: useTracker() in Presenter handlers

FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>

Output: [SEVERITY] file:line — description / Why: ... / Fix: ...
End with: EVPMR SUMMARY / Errors: N / Warnings: N / Suggestions: N
```

**Agent: fe-patterns**

```
Review the composition patterns, hooks discipline, and state location in this newly built feature:
- State in the right layer (URL > server > context > local)?
- No derived state synced with useEffect?
- useCallback/useMemo where re-renders matter?
- No components defined inside components?
- Hook return shape stable — no new object identity on every render?
- Redux only for genuinely shared cross-component state?

FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>

Output: [SEVERITY] file:line — description / Why: ... / Fix: ...
End with: PATTERNS SUMMARY / Errors: N / Warnings: N / Suggestions: N
```

**Agent: fe-a11y** _(only if interactive View components built)_

```
Review this newly built React Native / Next.js feature for accessibility:
Check accessible labels, roles, focus management, dynamic announcements, reduced motion support, touch target sizes, color contrast reliance, heading order.

FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>

Output: [SEVERITY] file:line — description / Why: ... / Fix: ...
End with: A11Y SUMMARY / Errors: N / Warnings: N / Suggestions: N
```

**Agent: fe-performance** _(only if Presenter with data fetching or complex state)_

```
Review this newly built feature for performance issues: waterfall data fetching, missing Promise.all, missing useCallback/useMemo, missing dynamic() imports, bundle size concerns, unnecessary re-renders, unstable key props.

FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>

Output: [SEVERITY] file:line — description / Why: ... / Fix: ...
End with: PERFORMANCE SUMMARY / Errors: N / Warnings: N / Suggestions: N
```

**Agent: adversarial** _(only if large module built)_

```
You are a devil's advocate reviewer. This is a newly built feature — argue the strongest case against shipping it as-is. Find risks, hidden assumptions, missing edge cases, over-engineering, or reasons this implementation could cause production issues. Be specific.

FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content>

Output: list of specific concerns, most severe first. No praise.
```

**Gate (Phase 5):** No `[ERROR]` findings remain before proceeding to tests.

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
[ERROR]      ...
[WARNING]    ...
[SUGGESTION] ...

[ADVERSARIAL CONCERNS]          ← only if adversarial agent ran
  ...

Tests:     PASS (N tests, N new)
Coverage:  Lines N% / Branches N% / Functions N% / Statements N%
Verdict:   DONE / BLOCKED — <list blockers>
```
