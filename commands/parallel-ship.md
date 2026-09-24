---
name: parallel-ship
description: Dynamic parallel pre-merge check with platform-routed gates (type/build + lint first, then test with coverage running alongside classifier-selected agents). Supports RN/web, Android, and iOS.
craftkitInject: parallel-classifier
---

**Commands:** `rtk git diff`, plus the platform's type/lint/test tooling (see Phase 1)
**Model:** everyday. Escalate for security-sensitive changes or major arch tradeoffs

> Triggered by: "parallel ship", "fast ship", "ship in parallel", "ship fast", `/parallel-ship`

---

## Step 0: Platform routing

1. Detect base: `rtk git remote show origin | grep 'HEAD branch'`
2. `rtk git diff <base>...HEAD --name-only` + `rtk git diff <base>...HEAD`
3. Detect platform per classifier Step 1.5 (`using-agent-skills`): RN/web, Android, or iOS. It selects the Phase 1 gates and the Phase 2 agent set.

---

## Phase 0: Context

Load context for the detected platform:
   - **RN / web:** apply standard context loading (`using-agent-skills`): freshness check (branch + commit), regenerate if stale or missing, read Summary + Key Changes
   - **Android / iOS:** derive context only for multi-screen branches (`/android-context`, `/ios-context`). Single screen: read a real sibling screen instead and pass that as the convention baseline

---

## Phase 1: Fast gates (all in parallel)

The gates split by cost. Type/build and lint finish in seconds and run first, as parallel Bash calls; a failure there stops the run before any agent tokens are spent. The test suite is the slowest gate and nothing the agents do depends on it, so it launches in the **same message** as the Phase 2 agents rather than before them, and wall-clock becomes the slower of the two instead of their sum. The price: a branch whose tests fail has still paid for its agent review, whose findings are reported alongside the failure.

| Platform | Type/build | Lint | Test (with coverage), launched in Phase 2 |
|----------|-----------|------|----------------------|
| RN / web | `rtk tsc --noEmit` | `rtk lint <changed-files>` | `rtk test --testPathPattern="<feature-path>" --coverage` |
| Android | n/a (Gradle compiles as part of test) | `./gradlew :<module>:lintGeneralDebug` | `./gradlew :<module>:testGeneralDebugUnitTest` (+ `jacocoTestReport` if the module has it) |
| iOS | n/a (Bazel compiles as part of test) | `swiftlint lint` | `bazelisk test //Modules/<M>:<M>TestsBundle` |

**Coverage gate:**
- **RN / web:** Lines, Branches, Functions, Statements all ≥ 93%. Below threshold → BLOCKED.
- **Android / iOS:** no fixed bar unless the team set one. Report the module's actual coverage; if it isn't measurable, say so rather than implying a pass.

**Gate:** Type/build and lint must pass before Phase 1.5. If either fails → report immediately, skip Phase 2. Tests and the coverage rule are judged when their run returns in Phase 2; a failure there makes the verdict BLOCKED whatever the agents found.

```
PHASE 1  (platform: <RN/web | Android | iOS>)
type/build: PASS / FAIL / n-a
lint:       PASS / FAIL
test:       launched with Phase 2
→ Proceeding to classification / BLOCKED: fix above first
```

---

## Phase 1.5: Classify

Apply the parallel workflow classifier injected above. Announce selected agents before proceeding.

---

## Phase 2: Tests + dynamic parallel agents

In **one** message: the platform's test command from Phase 1 as a Bash call with `run_in_background: true`, plus N `Agent` tool-use blocks for every selected agent, never in sequential waves. A test-only diff that selects no agents still runs the test command here. When the tests return, report the test and coverage lines from the Phase 1 box:

```
test:       PASS / FAIL (N tests)
coverage:   Lines N% / Branches N% / Functions N% / Statements N% → PASS / FAIL
            (native: actual module coverage, or "not measured")
```

The agents are independent (cold, read-only, no shared state) and must run concurrently; splitting them across turns serializes the slow ones behind the fast ones and is a defect. Agent definitions live in `agents/`, and the harness loads their system prompt and tool restrictions automatically. Each agent is cold, so pass content as the user message.

**Do not wait by polling.** Never `grep`/`sleep`-loop over task output files (`tasks/*.output`) to detect completion. The harness wakes the main thread automatically when every spawned agent and the background test run come to rest, and re-invokes you with their results. Spin-loops keep running for minutes after the agents already finished. On wake, read the returned results and go straight to Phase 3.

Every agent gets the same user message, prefixed `This is a pre-merge check. Be thorough.`.
**Pass full file contents, not just the diff.** An agent holding only a diff cannot see the
surrounding code, so it reads the files itself, and every read is a round-trip that re-sends its
whole growing context: three reads on a 20k base bills about `20 + 28 + 36 + 44`, not `44`.
Contents passed once cost once.

```
This is a pre-merge check. Be thorough.

CHANGED FILES (full contents):
<path>
```
<entire file>
```
… repeat per changed non-test source file

DIFF:
<full diff>

CONTEXT:
<the resolved intent file's `## Spec` when one exists, plus the Phase 0 derived Summary + Key Changes, or, for a single native screen, the sibling screen read in Phase 0>
```

**Bound it.** Non-test source files only, and skip any file over ~1500 lines. An omitted file is
named in the payload as `not provided`, which per `grounding` the agent reports rather than reading
or recalling.

Spawn the set the classifier selected:

| Agent (`subagent_type`) | Platform | Include when |
|-------------------------|----------|--------------|
| `code-quality` | all | any non-test, non-resource code changed |
| `ponytail-review` | all | any non-test, non-resource source changed |
| `fe-review` | RN / web | any EVPMR layer changed |
| `fe-performance` | RN / web | `View*.tsx` or `Presenter*.ts` changed |
| `fe-a11y` | RN / web | `View*.tsx` changed |
| `android-review` | Android | any MVP layer, Dagger, or `strings.xml` changed |
| `android-performance` | Android | Presenter/ViewModel/adapter/Composable changed |
| `android-a11y` | Android | Activity/Fragment/Widget/Composable or layout XML changed |
| `ios-review` | iOS | any MVVM-C layer or `*.strings` changed |
| `ios-performance` | iOS | ViewModel/ViewController/Fetcher/Cell changed |
| `ios-a11y` | iOS | ViewController/View/Cell changed |
| `adversarial` | all | 3+ architecture layers changed |

**`code-quality` prompt additions**, prepended when applicable:
- security-sensitive paths (`auth/*`, `payment/*`, `*credential*`, `*token*`): `"Security-sensitive code present. Emphasize security axis."`
- manifest changed (`package.json`, `*.gradle`, `Podfile`/`Package.swift`): `"<file> changed. Audit new dependencies for bundle/binary impact, maintenance status, and known vulnerabilities."`
- a feature flag, remote config, toggle, or experiment is read in the diff: `"Flag-gated diff. Check the OFF path: shared code both paths call, state written while ON, renamed events, and response fields the OFF path must tolerate. An OFF path whose behavior changed is an [ERROR]."`

---

## Phase 3: Synthesize

Apply **Step 5: Handle agent failures** from the injected classifier: any selected agent that returned no findings is a coverage gap, not a clean axis, so surface it, mark it skipped, and gate the verdict to `INCOMPLETE` (never `READY TO MERGE` with an infra-skipped review agent).

This is a pre-merge code review → apply **Track B** (structured synthesis). Deduplicate by `file:line`, then classify each finding's confidence:

- `[CONSENSUS]`: flagged by 2+ agents independently → highest-confidence signal, fix first
- Standard: flagged by one agent
- `[UNIQUE]`: notable finding from one agent, not corroborated → preserve, note lower confidence

**Surface contradictions explicitly.** If two agents recommend different fixes for the same location, state both and adjudicate, preferring whichever has evidence over assertion. Never silently average conflicting recommendations.

Adversarial findings are **blind spots**: what all review agents missed. Surface them as a separate block.

**Rollback gate.** A diff that reads a flag reports its rollback state. An OFF path that nobody verified, or a missing `flag:` marker, is a blocker, not a suggestion, because it is the difference between a one-click rollback and a hotfix.

Sort within each tier: `[CONSENSUS]` first, then standard, then `[UNIQUE]`.

```
PARALLEL SHIP COMPLETE
────────────────────────────────────────
Platform:  <RN/web | Android | iOS>
Phase 1:   type/build PASS | lint PASS | test PASS (N tests)
           Coverage: Lines N% / Branches N% / Functions N% / Statements N%  (native: actual, or "not measured")
Agents:    ran [list] | skipped [agent + reason, if any]
Rollback:  <flag key>: OFF path verified <how> | n-a (no flag in diff)

FINDINGS
[ERROR][CONSENSUS]   file:line: description  (caught by: agent-a + agent-b)
                       Why: ...
                       Fix: ...
[ERROR]              file:line: description
                       Why: ...
                       Fix: ...
[WARNING][UNIQUE]    file:line: description  (agent-name only, lower confidence)
                       Why: ...
                       Fix: ...
[SUGGESTION]         ...

[BLIND SPOTS]                    ← only if adversarial agent ran
  1. concern → scenario → consequence
  2. ...

SUMMARY
Consensus findings: N  (2+ agents, highest confidence)
Errors:      N  (must fix before merge)
Warnings:    N
Suggestions: N
Skipped:     N  (infra failures: coverage gaps, not clean)
Verdict: READY TO MERGE / BLOCKED (<list blockers>) / INCOMPLETE (<axes unverified due to skipped agents>)
```

---

## Phase 4: Document (opt-in, only if verdict READY TO MERGE)

Code is final at this point, which is the natural moment to capture the *why* and explain the *what*. Offer, never auto-run:

```
→ Before merge, capture documentation and score the run? (all optional)
  (a) /adr  → record any architectural decision made on this branch (the why)
  (d) /docs → write engineer + stakeholder documentation for this feature
  (e) /eval → score this run into a weighted correctness %, append to the ledger
  (n) skip
```

- **`/adr`**: if the branch made a non-obvious, hard-to-reverse decision, run `/adr` to record it and link it into the feature's `docs/planning/` intent file. One ADR per decision; skip for reversible/local choices.
- **`/docs`**: run `/docs` to produce the dual-audience pair (technical + stakeholder), humanized. Pulls from the intent file + ADRs + the diff.
- **`/eval`**: run `/eval` to turn this run into a number. Pass it the Phase 1 gate results and the resolved intent file, which it needs and cannot re-derive; it spawns `eval-judge`, appends a row to `docs/evals/ledger.md`, and derives the running success rate. Worth it on any branch built by a workflow, since a score with no prior rows is a data point and a hundred rows is a regression detector.

Skip entirely if the user declines or the change is trivial. Do not block merge on documentation.
