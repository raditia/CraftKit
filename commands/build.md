---
name: build
description: Full feature build workflow — orchestrates fe-context, fe-scaffold, fe-patterns, fe-performance, fe-review, fe-test in sequence. Use when building a new feature or screen.
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk jest`, `rtk lint`
**Model:** everyday — escalate for architectural decisions with non-obvious tradeoffs

> Triggered by: "build feature X", "create a new screen for X", "scaffold a new module", "implement feature X"

---

## How to run this workflow

Execute each step in order. Each step has a gate — do not proceed until the gate passes.

---

## Step 0 — Platform routing

Detect the platform from the project root + changed files, then dispatch:

- **Android** (`settings.gradle`/`build.gradle`, `*.kt`/`*.java`) → `/android-scaffold` (Step 2) → `/android-patterns` + `/android-performance` while implementing (Step 3) → `/android-review` (Step 4) → `/android-test` (Step 5). Gates below become their `./gradlew :<module>:lintGeneralDebug` + `:testGeneralDebugUnitTest` equivalents. **Skip the EVPMR steps.**
- **iOS** (`*.xcodeproj`/`Podfile`/`Package.swift`, `Modules/` + `*.swift`) → `/ios-scaffold` → `/ios-patterns` + `/ios-performance` → `/ios-review` → `/ios-test`. Gates become `swiftlint` + `bazelisk test //Modules/<M>:<M>TestsBundle`. **Skip the EVPMR steps.**
- **React Native / web** (`package.json` + `*.tsx`, EVPMR) → continue with the steps below.

For native, Step 1 context is optional — run `/android-context` or `/ios-context` only for multi-screen branches; otherwise read a real sibling screen first.

---

## Step 1 — Context

Run the `/fe-context` workflow:
1. Detect base branch: `rtk git remote show origin | grep 'HEAD branch'`
2. Diff: `rtk git log --oneline <base>...HEAD` and `rtk git diff <base>...HEAD`
3. Read `docs/context.md` if it exists — skip re-generating if diff matches
4. Write `docs/context.md` with sections: Summary, Architecture Patterns in Use, Key Changes, Test Coverage Needed
5. Hard limit: ≤ 600 lines

**Gate:** `docs/context.md` exists and covers the feature scope.

---

## Step 2 — Scaffold

Follow the `/fe-scaffold` workflow — surface assumptions first, then create the 5-file EVPMR module. Apply all TypeScript, styling, and layer rules from that skill.

**Gate:** All 5 files created, `rtk tsc --noEmit` passes.

---

## Step 3 — Implement

Apply `/fe-patterns` (state location, hooks discipline, data fetching) and `/fe-performance` (waterfall elimination, bundle size, RN specifics) continuously as you build — not as a post-pass. `fe-rules` (always active) enforces layer constraints and React correctness throughout.

**Gate:** `rtk tsc --noEmit` passes after every logical chunk.

---

## Step 4 — Review

Run the `/fe-review` checklist. Flag issues as `[ERROR]` / `[WARNING]` / `[SUGGESTION]`. Run `rtk tsc --noEmit` and `rtk lint`.

**Gate:** No `[ERROR]` items remain, tsc and lint clean.

---

## Step 5 — Test

Write tests covering all new code paths:

- All discriminated union states: `NOT_ASKED`, `LOADING`, `DATA_READY`, `ERROR`
- All user interactions and tracking calls
- Every `if/else`, ternary, and optional chaining fallback
- Run: `rtk test --testPathPattern="path/to/__tests__/FileName" --no-coverage`
- Coverage: `rtk test --testPathPattern="path/to/feature" --coverage` — Lines, Branches, Functions, Statements all ≥ 93%

**Gate:** All tests pass. Coverage ≥ 93% on all four metrics.

---

## Done

Report:
- Files created (list all 5)
- `rtk tsc --noEmit` result
- `rtk lint` result
- Tests added, pass/fail count, coverage numbers
