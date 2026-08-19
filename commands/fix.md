---
name: fix
description: Bug fix workflow — orchestrates fe-context, debug (reproduce → isolate → fix), and fe-test to verify the fix holds. Use when something is broken.
---

**Commands:** `rtk tsc`, `rtk lint`, `rtk grep "pattern" .`
**Tests:** `rtk test --testPathPattern=<path> --no-coverage` (run from workspace root)
**Model:** everyday — escalate if no clear hypothesis after 2 isolation attempts

> Triggered by: "something is broken", "fix this bug", "this test is failing", "this crashes", "why is X not working"

---

## How to run this workflow

Run the `/debug` skill workflow in full: Reproduce → Isolate → Hypothesize → Fix → Verify. Never skip to fix without a hypothesis. `/debug` is platform-agnostic.

---

## Step 0 — Platform routing

Detect the platform from the changed/failing files. The debug loop is identical; only the verify tooling changes:

- **Android** (`*.kt`/`*.java`) → regression test via `/android-test`; verify with `./gradlew :<module>:testGeneralDebugUnitTest` + `:lintGeneralDebug`. No fixed 93% coverage bar.
- **iOS** (`*.swift`/`*.m`) → regression test via `/ios-test`; verify with `bazelisk test //Modules/<M>:<M>TestsBundle` + `swiftlint lint`. No fixed 93% coverage bar.
- **React Native / web** → the `rtk tsc` / `rtk test` gates below apply (coverage ≥ 93%).

---

## Step 1 — Context

1. Detect base branch: `rtk git remote show origin | grep 'HEAD branch'`
2. Apply standard context loading (`using-agent-skills`) — freshness check (branch + commit), regenerate if stale or missing, read Summary + Key Changes
3. Capture the exact failure: error message, stack trace, failing test output

---

## Steps 2–5 — Debug

Follow the `/debug` workflow exactly:
- **Reproduce:** confirm bug is reproducible; write a failing test before touching code
- **Isolate:** narrow to specific file and line — not "somewhere in the flow"
- **Hypothesize:** `HYPOTHESIS / EXPECTED / ACTUAL / FIX PLAN` before any code change; escalate if no hypothesis after 2 attempts
- **Fix:** surgical changes only — every changed line traces to the hypothesis; `rtk tsc --noEmit` + `rtk lint` must pass
- **Bloat check:** apply `/ponytail-review` to the fix diff (main-thread — diff is small, no agent spawn). A fix must not smuggle in speculative abstraction or a new indirection layer; if it did, cut it before verifying. Skip only for a one-line diff.

---

## Step 6 — Verify

```bash
rtk test --testPathPattern="path/to/feature" --no-coverage
rtk test --testPathPattern="path/to/feature" --coverage
```

All tests pass. Coverage ≥ 93%. Add a regression test — the failing scenario must be permanently covered.

**Gate:** All tests pass. Coverage ≥ 93%. Regression test exists.

---

## Done

Report:
- Root cause (1–2 sentences)
- Files changed (list)
- Regression test added (yes/no + test name)
- `rtk tsc --noEmit` result
- `rtk test --coverage` numbers
