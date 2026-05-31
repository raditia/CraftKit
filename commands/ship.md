---
name: ship
description: Pre-merge readiness workflow — orchestrates fe-test (coverage gate), code-review (5-axis), and fe-review (EVPMR). Use when preparing a branch for PR.
---

**Commands:** `rtk jest`, `rtk tsc`, `rtk lint`, `rtk git diff`
**Model:** everyday — escalate for security-sensitive changes or major arch tradeoffs

> Triggered by: "get this ready to merge", "ship this", "prepare for PR", "pre-merge check", "is this ready?"

---

## How to run this workflow

Three gates in order: tests pass → coverage met → review clean. All three must be green before declaring done.

---

## Step 1 — Context

1. Detect base branch: `rtk git remote show origin | grep 'HEAD branch'`
2. Run: `rtk git diff <base>...HEAD --name-only`
3. Read `docs/context.md` if present (selective: Summary + Key Changes only)

---

## Step 2 — Tests

Run the full test suite for every changed file:
```bash
rtk jest path/to/feature/
```

Fix any failures. Do not proceed with failing tests.

**Gate:** All tests pass.

---

## Step 3 — Coverage

```bash
rtk jest --coverage path/to/feature/
```

Lines, Branches, Functions, Statements all ≥ 93%. Add tests until threshold is met.

Check for untested paths in the diff:
- All discriminated union states covered (`NOT_ASKED`, `LOADING`, `DATA_READY`, `ERROR`)
- All user interactions tested
- All error branches tested

**Gate:** Coverage ≥ 93% on all four metrics.

---

## Step 4 — Type check + lint

```bash
rtk tsc --noEmit
rtk lint path/to/changed/files
```

Fix all errors. No `// eslint-disable` without a documented reason.

**Gate:** Zero type errors, zero lint errors.

---

## Step 5 — Review

Run the `/review` command — applies `/code-review` (5-axis: correctness, readability, architecture, security, performance) and `/fe-review` (EVPMR checklist). Use severity labels from `/using-agent-skills`.

**Gate:** No `[ERROR]` findings remain.

---

## Done

Report:
```
SHIP READINESS
Tests:     PASS (N tests, N new)
Coverage:  Lines N% / Branches N% / Functions N% / Statements N%
TypeCheck: PASS / FAIL
Lint:      PASS / FAIL
Review:    N errors / N warnings / N suggestions
Verdict:   READY TO MERGE / BLOCKED (list blockers)
```
