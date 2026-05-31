---
name: fix
description: Bug fix workflow — orchestrates fe-context, debug (reproduce → isolate → fix), and fe-test to verify the fix holds. Use when something is broken.
alwaysApply: false
---

**Commands:** `rtk jest`, `rtk tsc`, `rtk lint`, `rtk grep "pattern" .`
**Model:** everyday — escalate if no clear hypothesis after 2 isolation attempts

> Triggered by: "something is broken", "fix this bug", "this test is failing", "this crashes", "why is X not working"

---

## How to run this workflow

Five steps: reproduce → isolate → hypothesize → fix → verify. Never skip to fix without a hypothesis.

---

## Step 1 — Context

1. Detect base branch: `rtk git remote show origin | grep 'HEAD branch'`
2. Read `docs/context.md` if present (selective: Summary + Key Changes only)
3. Capture the exact failure: error message, stack trace, failing test output, reproduction steps

---

## Step 2 — Reproduce

Confirm the bug is reproducible:
```bash
rtk jest path/to/__tests__/FileName.test.tsx   # failing test
rtk tsc --noEmit                                # type errors
rtk lint path/to/file                           # lint errors
```

If the bug is a runtime behavior:
- Write a failing test that captures the exact failure before touching any code
- The test must fail for the right reason — not just "error thrown" but the specific assertion

**Gate:** Failure is reproducible and documented.

---

## Step 3 — Isolate

Narrow to the smallest change that triggers the failure:

1. Bisect if needed: `rtk git bisect start`, `rtk git bisect bad`, `rtk git bisect good <hash>`
2. Comment out code paths to identify which line/function is responsible
3. Check recent changes: `rtk git log --oneline -10`, `rtk git diff HEAD~1`
4. Grep for related patterns: `rtk grep "functionName" .`

State what you find:
```
ISOLATED: the failure occurs in PresenterX.ts:42 when Y returns null
```

**Gate:** Single root cause identified. Not "somewhere in the flow" — specific file and line.

---

## Step 4 — Hypothesize

Before writing any fix, state the hypothesis:
```
HYPOTHESIS: [what is wrong and why]
EXPECTED:   [what should happen]
ACTUAL:     [what happens instead]
FIX PLAN:   [one-sentence description of the change]
```

If you cannot form a clear hypothesis after 2 isolation attempts:
```
ESCALATE:
Reason: no clear hypothesis after 2 isolation attempts
Recommended: claude-opus-4-7
Claude Code: /model claude-opus-4-7 → re-invoke /fix
```

---

## Step 5 — Fix

**Surgical changes only** — touch only what is needed to fix the root cause:
- Do not refactor code adjacent to the fix
- Do not remove pre-existing dead code (mention it, don't delete it)
- Do not add features "while you're in there"
- Every changed line must trace directly to the hypothesis

After fixing:
```bash
rtk tsc --noEmit
rtk lint path/to/changed/file
```

**Gate:** Type check and lint pass.

---

## Step 6 — Verify

Run the full test suite for the affected area:
```bash
rtk jest path/to/feature/
rtk jest --coverage path/to/feature/
```

All must pass. Coverage must stay ≥ 93%. If coverage drops, add tests.

Add a regression test if one didn't exist — the failing scenario should be permanently covered.

**Gate:** All tests pass. Coverage ≥ 93%. Regression test exists for this bug.

---

## Done

Report:
- Root cause (1–2 sentences)
- Files changed (list)
- Regression test added (yes/no + test name)
- `rtk tsc --noEmit` result
- `rtk jest --coverage` numbers
