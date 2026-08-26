---
name: parallel-build
description: Dynamic parallel build workflow with platform-routed context + scaffold + implement, then classifier-selected validation agents running concurrently. Supports RN/web (EVPMR), Android (MVP), and iOS (MVVM-C).
---

**Commands:** `rtk git diff`, plus the platform's type/lint/test tooling (see Step 0)
**Model:** everyday. Escalate for architectural decisions with non-obvious tradeoffs

> Triggered by: "parallel build", "build in parallel", "build fast", `/parallel-build`

---

## Step 0: Platform routing

Detect the platform from the project root + target files, then use its column for every phase below:

| | RN / web (EVPMR) | Android (MVP) | iOS (MVVM-C) |
|---|---|---|---|
| **Signal** | `package.json` + `*.tsx` | `*.gradle`, `*.kt`/`*.java` | `*.xcodeproj`/`Podfile`/`Package.swift`, `Modules/` + `*.swift` |
| **Phase 0 context** | `/fe-context` → `docs/context.md` (required) | `/android-context` only if multi-screen | `/ios-context` only if multi-screen |
| **Phase 1 scaffold** | `/fe-scaffold` (5-file EVPMR) | `/android-scaffold` | `/ios-scaffold` |
| **Phase 2 patterns** | `/fe-patterns` + `/fe-performance` | `/android-patterns` + `/android-performance` | `/ios-patterns` + `/ios-performance` |
| **Phase 3 gates** | `rtk tsc --noEmit`, `rtk lint` | `./gradlew :<module>:lintGeneralDebug` | `swiftlint lint` |
| **Phase 6 tests** | `/fe-test`, coverage ≥ 93% | `/android-test`, no fixed bar | `/ios-test`, no fixed bar |

For native, skip the EVPMR-specific steps. When Phase 0 context is skipped (single screen), read a real sibling screen first and use it as the convention baseline everywhere `docs/context.md` is referenced below.

---

## Phase 0: Context (sequential)

Run the platform's context step from Step 0. For RN / web that is `/fe-context`:
1. Detect base: `rtk git remote show origin | grep 'HEAD branch'`
2. `rtk git log --oneline <base>...HEAD` + `rtk git diff <base>...HEAD`
3. Write `docs/context.md` (≤ 600 lines): Summary, Architecture Patterns in Use, Key Changes, Test Coverage Needed

**Gate:** `docs/context.md` exists and covers the feature scope, or, for a single native screen, the sibling screen has been read.

If the architecture/approach is genuinely open (not a routine feature on the platform's pattern) → offer `/ideate` before scaffold; feed the chosen shortlist in as the design decision. Opt-in, and the cost gate applies.

---

## Phase 1: Scaffold (sequential)

Follow the platform's scaffold skill from Step 0: surface assumptions first, create the module's full file set.

**Gate:** All files created, the platform's type/build gate passes.

---

## Phase 2: Implement (sequential)

Build the feature. Apply the platform's patterns + performance skills continuously as you build, not as a post-pass. On RN / web, `fe-rules` (always active) enforces layer constraints throughout; on native, the layer contract comes from the platform's patterns skill.

**Gate:** The platform's type/build gate passes after every logical chunk, and the ponytail self-pass (`karpathy-guidelines` rule 2) runs on the built files before Phase 3, so you cut or mark `ponytail:` now, while the code is still yours. The `ponytail-review` agent in Phase 5 is the backstop, not the first pass; findings there mean this gate was skipped.

---

## Phase 3: Fast gates (parallel)

Run the platform's Phase 3 gates from Step 0 simultaneously as parallel Bash calls.

**Gate:** All must pass. If any fail → fix before Phase 4.

```
PHASE 3  (platform: <RN/web | Android | iOS>)
type/build: PASS / FAIL / n-a
lint:       PASS / FAIL
→ Proceeding to classification / BLOCKED: fix above first
```

---

## Phase 4: Classify what was built

Apply the parallel workflow classifier from `using-agent-skills`, but scan the **newly created/modified files** (not just the diff), reading their actual content to determine which layers exist and what they do.

Additional build-specific rules, where the a11y/performance rows resolve to the detected platform's agent (`fe-*`, `android-*`, or `ios-*`):

| What was built | Add to agent set |
|----------------|-----------------|
| Any non-test, non-resource source | `ponytail-review` (over-engineering: fresh builds accrete speculative abstraction) |
| Screen/view with form inputs or interactive elements | platform a11y agent |
| Screen/view reachable from navigation | platform a11y agent |
| Presenter / ViewModel with data fetching or complex state | platform performance agent |
| List or collection rendering (FlatList, RecyclerView, UITableView/UICollectionView) | platform performance agent |
| Large module (> 5 files or > 300 lines total) | `adversarial` |

Announce the detected platform and the selected agents before proceeding.

---

## Phase 5: Dynamic parallel validation agents

Spawn **all** selected agents in **one** message: N `Agent` tool-use blocks in a single response, never in sequential waves. They are independent (cold, read-only, no shared state) and must run concurrently; splitting them across turns serializes the slow ones behind the fast ones and is a defect. Agent definitions live in `agents/`, and the harness loads their system prompt and tool restrictions automatically. Each agent is cold, so pass content as the user message. Pass full file contents, not just the diff, because agents need the full implementation context.

**Do not wait by polling.** Never `grep`/`sleep`-loop over task output files (`tasks/*.output`) to detect completion. The harness wakes the main thread automatically when every spawned agent comes to rest, and re-invokes you with their results. Spin-loops keep running for minutes after the agents already finished. On wake, read the returned results and go straight to synthesis.

Every agent gets the same user message:

```
FILES:
<content of all newly created/modified files>

CONTEXT:
<docs/context.md full content, or, for a single native screen, the sibling screen read in Phase 0>
```

`adversarial` gets one extra prefix line: `This is a newly built feature. Argue the strongest case against shipping it as-is.`

Spawn the set Phase 4 selected:

| Agent (`subagent_type`) | Platform | Include when |
|-------------------------|----------|--------------|
| `ponytail-review` | all | any non-test, non-resource source built |
| `fe-review` | RN / web | always |
| `fe-patterns` | RN / web | always |
| `fe-a11y` | RN / web | interactive or navigable View built |
| `fe-performance` | RN / web | Presenter with data fetching, complex state, or list rendering |
| `android-review` | Android | always |
| `android-a11y` | Android | interactive or navigable Activity/Fragment/Widget/Composable built |
| `android-performance` | Android | Presenter/ViewModel with data fetching, complex state, or RecyclerView |
| `ios-review` | iOS | always |
| `ios-a11y` | iOS | interactive or navigable ViewController/View built |
| `ios-performance` | iOS | ViewModel/Fetcher with data fetching, complex state, or table/collection view |
| `adversarial` | all | large module built (> 5 files or > 300 lines total) |

Native has no `*-patterns` cold agent, because the platform's patterns skill already ran continuously in Phase 2, and its review agent covers the layer contract. That is a deliberate gap, not an omission to fill.

**Synthesize Phase 5 findings.** First apply **Step 5: Handle agent failures** (`using-agent-skills`): any selected agent that returned no findings is a coverage gap, not a clean axis, so surface it, mark it skipped, gate verdict to `INCOMPLETE`. Then apply **Track B** (structured synthesis):
- `[CONSENSUS]`: flagged by 2+ agents independently → fix before proceeding
- Standard: flagged by one agent
- `[UNIQUE]`: notable finding from one agent only → preserve, note lower confidence
- Adversarial findings → **blind spots** block (what review agents missed as a whole)

**Gate (Phase 5):** No `[ERROR]` findings (consensus or single-agent) remain before proceeding to tests.

---

## Phase 6: Tests (sequential)

Run the platform's test skill from Step 0 and write tests covering all new code paths.

**Gate:** All tests pass. RN / web: coverage ≥ 93% on Lines, Branches, Functions, Statements. Android / iOS: no fixed bar unless the team set one, so report the module's actual coverage, or state that it isn't measured.

---

## Done

```
PARALLEL BUILD COMPLETE
────────────────────────────────────────
Platform:        <RN/web | Android | iOS>
Files created:   [list all files in the module]
Ponytail:        self-pass clean / cut <what>, marked <what>
Phase 3:         type/build PASS | lint PASS
Agents (Phase 5): ran [list] | skipped [agent + reason, if any]

FINDINGS (from validation)
[ERROR][CONSENSUS]   file:line: description  (caught by: agent-a + agent-b)
[ERROR]              file:line: description
[WARNING][UNIQUE]    file:line: description  (agent-name only, lower confidence)
[SUGGESTION]         ...

[BLIND SPOTS]                    ← only if adversarial agent ran
  1. concern → scenario → consequence

Tests:     PASS (N tests, N new)
Coverage:  Lines N% / Branches N% / Functions N% / Statements N%  (native: actual, or "not measured")
Verdict:   DONE / BLOCKED (<list blockers>) / INCOMPLETE (<axes unverified due to skipped agents>)
```
