---
slug: test-heal
status: active
created: 2026-09-28
---

# Self-healing step for the platform test skills

## Spec
**Updated:** 2026-09-28 · **By:** /spec

- **Objective:** When existing unit tests fail after a change, `/fe-test`, `/android-test` and `/ios-test` repair the ones that are stale without masking a real regression. Today they carry only "fix failures; never skip", which leaves the model free to change an assertion to match a bug.
- **Users & job:** Developers running a platform test skill in a consumer repo, either while writing tests for a diff or on a "fix tests" request.
- **Success:**
  1. Every failing test is sorted into exactly one heal class before any edit, and the class is named in the report.
  2. An expected value or assertion changes only when the resolved spec or an approved `<slug>.tests.md` row backs the new behavior; otherwise the run stops and hands off to `/fix`.
  3. Every heal is reported as `healed: <test> <class> <evidence>`, and every stop as `stopped: <test> <reason>`.
  4. `bash check.sh` exits 0 with a new check that fails when any of the three skills stops injecting `test-heal`.
  5. `bash sync.sh` succeeds and a second consecutive run reports up to date everywhere.
- **In scope:**
  - `partials/test-heal.md`: platform-neutral classes, allowed action per class, the STOP rule, the report lines.
  - `craftkitInject: ..., test-heal` in all three skills, plus a one-line pointer in each skill's run step.
  - README (partials/feature notes), CHANGELOG section, version bump to v1.47.0, the `check.sh` check.
- **Out of scope:**
  - E2E locator healing (Detox, Maestro, Appium, Espresso, XCUITest).
  - Retries or quarantine of flaky tests, which the partial forbids outright.
  - A new standalone skill, slash command, or routing entry.
  - Editing production code; a suspected regression goes to `/fix`.
- **Constraints:** One partial serves Jest, JUnit+MockK and Quick+Nimble, so class names describe the failure, not a framework. Obeys `grounding` (each heal carries evidence) and karpathy rule 5 (tests keep intent). No em-dashes. `check.sh` stays bash 3.2.
- **Key decisions:**
  - Classes and actions:

    | Class | Signal | Action |
    |---|---|---|
    | `rename` | Symbol, testID, accessibility id or resource key the test references was renamed in the diff | Heal: point the test at the new name, citing the diff line |
    | `mock-shape` | Mock or fixture no longer matches a type or interface the diff changed | Heal: add or rename fields, never change an asserted value, then run the type check |
    | `snapshot` | Snapshot differs, and the diff touched the rendering file it covers | Heal only when every changed hunk of the snapshot maps to a cited diff line or intent row; update by named test, never a bulk update (`jest -u` rewrites every failing snapshot in the run). Any unexplained removed or changed node → `expectation` |
    | `timing` | Failure depends on real time or ordering, not on values | Cite the diff line that added the async or ordering dependency, then heal the wait (fake timers, awaited assertion, Turbine/`toEventually`); no such line → STOP; never add a retry |
    | `expectation` | Expected value, assertion, or call count differs | STOP unless intent backs it (see below) |
  - Scope: the partial applies only to tests that already exist at the merge-base with the base branch. Tests written in this run have no stale baseline, so they get fixed as authored code.
  - Intent backing for `expectation`: an approved `<slug>.tests.md` row or a Spec line states the new expected value or behavior the rewritten assertion checks, and it contradicts the old one. The quote goes in the `healed:` line. A test titled with a TC ID is governed only by that row. A row approved or edited during this run counts as no intent. No intent file, always STOP.
  - Most conservative class wins when a failure fits several (`expectation` beats all).
  - Test for a file outside the diff fails, and the failing line does not reference a symbol the diff changed → STOP as a likely regression. A `rename`/`mock-shape` heal outside the diff must cite the changed symbol's diff line.
  - After healing, one wider run: the module's unit suite (or every test importing a changed symbol), with a before/after list of failing tests. A heal that adds a new failure is reverted, then STOP. Without this run, the guards above never fire, because each skill's run step covers only the changed test files.
  - Delivered as a partial, not a skill, because it is a step inside three skills; one copy avoids three drifting versions.
- **Risks & open questions:**
  - The model can misclassify an `expectation` change as `rename` or `mock-shape`. Mitigation: each heal must cite the diff line that justifies it, and `mock-shape` may add or rename fields but never change an asserted value.
  - plan-roaster (5/10) found that the first draft let `snapshot` heal without intent and that its guards could never fire under the skills' narrow run. Both are addressed in Key decisions above.
  - Assumed: the step runs inside each skill's existing run step (writing tests or "fix tests"), and `/fix` does not call it directly.
- **Acceptance:**
  - [ ] `partials/test-heal.md` exists with the five classes, the STOP rule and both report lines.
  - [ ] fe-test, android-test and ios-test list `test-heal` in `craftkitInject` and point to it from their run step.
  - [ ] The rendered installed skills contain the partial body (checked after sync).
  - [ ] The new `check.sh` check fails when the inject is removed from one skill, and passes when restored.
  - [ ] `bash check.sh` exits 0; the second `bash sync.sh` run reports up to date.
  - [ ] README, CHANGELOG (v1.47.0), `package.json` version and README header all agree.

## Task Plan
**Updated:** 2026-09-28 · **By:** /plan

| ID | Task | Acceptance | Depends on | TCs | Executes via |
|----|------|-----------|-----------|-----|--------------|
| T1 | Branch `feat/test-heal` off `main`, commit this intent file | `git log -1` on the branch shows the file | none | none | direct git |
| T2 | Write `partials/test-heal.md`: five classes, intent-backing rule, guards, `healed:` / `stopped:` lines | File holds all five class names, `stopped:`, "never add a retry", "No intent file, always STOP", the merge-base scope line, and the wider after-heal run; check 19 (em-dash) passes | T1 | none | direct edit |
| T3 | Add `test-heal` to `craftkitInject` in fe-test, android-test, ios-test, and point each run step at it | Each frontmatter matches `^craftkitInject:.*test-heal`; each run step names `test-heal` | T2 | none | direct edit |
| T4 | Add a `check.sh` check beside the test-cases-resolve block: partial exists, still contains the literal "No intent file, always STOP" and "never a bulk update", all three skills inject it | Removing the inject from one skill makes the check fail; restoring it passes | T3 | none | direct edit |
| T5 | README partials paragraph (line ~1291), CHANGELOG `v1.47.0`, `package.json` + README header bump | Version check passes; README names `partials/test-heal.md` | T2 | none | direct edit |
| T6 | Full verification | `bash check.sh` exits 0; `bash sync.sh` prints `Sync complete.`; second run all up to date; installed `~/.claude/commands/fe-test.md` contains the partial body | T4, T5 | none | `bash check.sh`, `bash sync.sh` |

**Parallelizable now:** T1
**Parallelizable after T2:** T3, T5
**Critical path:** T1 → T2 → T3 → T4 → T6

## Decisions
_(pointers appended by /adr)_
