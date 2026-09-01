---
name: parallel-classifier
description: Dynamic agent-selection classifier shared by the parallel-* orchestrators. Spliced into each at sync time; never loaded always-on.
---

## Parallel workflow: dynamic classifier

Used by `/parallel-review`, `/parallel-ship`, `/parallel-build`. Run this classification step before spawning any Phase 2 agents.

### Step 1: Read the diff and actual changed files

```bash
rtk git diff <base>...HEAD --name-only   # file list
rtk git diff <base>...HEAD               # full diff
```

For each changed file, read enough of its actual content to confirm what layer it belongs to. Don't rely on filename alone.

### Step 1.5: Detect platform

The routing hook already injects `Platform (detected from cwd)` each turn, so take it and skip this step. The table below is for when it is absent (non-Claude tool, no marker found) or when the diff is genuinely mixed, in which case run both tables and union the sets:

| Signal | Platform | Architecture |
|--------|----------|--------------|
| `*.tsx`/`*.ts` + `package.json` | React Native / web | EVPMR |
| `*.kt`/`*.java` + Gradle | Android | MVP + Core framework |
| `*.swift`/`*.m` + `Modules/` | iOS | MVVM-C |

`code-quality`, `ponytail-review`, and `adversarial` are platform-agnostic and apply on all three. Only the review/a11y/performance agents are platform-specific.

### Step 2: Classify and select agents

**React Native / web (EVPMR)**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `View*.tsx` | `fe-review`, `fe-a11y` |
| `Presenter*.ts` | `fe-review`, `code-quality` |
| `Model*.ts` | `code-quality` |
| `Entry*.tsx` | `fe-review` |
| `Resource*.ts` | `fe-review` |
| `package.json` changed | `code-quality` (dependency audit, note in prompt) |
| Test files only (all match `__tests__/*` or `*.test.*`) | **Skip Phase 2**, fast gates only |

**Android (MVP + Core framework)**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `*Activity.kt`, `*Fragment.kt`, `*Widget.kt`, `res/layout/*.xml`, `@Composable` | `android-review`, `android-a11y` |
| `*Presenter.kt` | `android-review`, `code-quality` |
| `*ViewModel.kt`, `*NavigationModel.kt` | `android-review`, `code-quality` |
| `*Repository.kt`, `*Interactor.kt`, `*UseCase.kt` | `code-quality` |
| `*Module.kt`, `*Component.kt`, `*ComponentBuilder.kt` (Dagger) | `android-review` |
| `res/values*/strings.xml` | `android-review` |
| `*.gradle` / `*.gradle.kts` changed | `code-quality` (dependency audit, note in prompt) |
| Test files only (all match `src/test/**` or `*Test.kt`) | **Skip Phase 2**, fast gates only |

**iOS (MVVM-C)**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `*ViewController.swift`, `*View.swift`, `*Cell.swift` | `ios-review`, `ios-a11y` |
| `*ViewModel.swift` | `ios-review`, `code-quality` |
| `*Fetcher.swift` | `code-quality`, `ios-performance` |
| `*Contract.swift`, `*Factory.swift`, `*Coordinator.swift` | `ios-review` |
| `*.strings`, `Localizable*` | `ios-review` |
| `Podfile`, `Package.swift`, `BUILD`/`*.bzl` changed | `code-quality` (dependency audit, note in prompt) |
| Test files only (all match `*Test.swift` or `*Spec.swift`) | **Skip Phase 2**, fast gates only |

**All platforms**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `auth/*`, `payment/*`, `*credential*`, `*token*` | `code-quality` (security emphasis, note in prompt) |

Dedup the set. Always include `code-quality` if any non-test, non-resource code changed.

> `parallel-build` and `parallel-ship` additionally include `ponytail-review` (over-engineering axis) for any non-test, non-resource change, defined in those command files, not this base table (see extensions note below). It overlaps `code-quality` only on `delete:`/dead-code; a same-`file:line` hit becomes `[CONSENSUS]` in synthesis, which is the dedup, not waste.

> **Command-specific extensions:** `parallel-build` and `parallel-ship` add agents beyond these base tables (e.g. `fe-patterns`, `fe-performance`, `android-performance`, `ios-performance`). Those additions are defined in the command file itself, not here; these tables are the shared base.

### Step 3: Flag conditions

Evaluate before spawning:

| Condition | Action |
|-----------|--------|
| Diff > 300 lines | Add `[WARNING] Change size: N lines, consider splitting` to synthesis |
| 3+ architecture layers changed: EVPMR (Entry/View/Presenter/Model/Resource), Android MVP (View/Presenter/ViewModel/Repository/DI), or iOS MVVM-C (ViewController/View/ViewModel/Fetcher/Coordinator) | Add `adversarial` agent (definition in `agents/adversarial.md`) |
| Security-sensitive paths | Pass "Security-sensitive code present. Emphasize security axis." in user message to `code-quality` agent |
| `docs/context.md` has a PLANNING block | Pass "Spec conformance: verify the diff implements the PLANNING block's spec and acceptance criteria; flag drift between what was planned and what was built." in user message to `code-quality` agent |

### Step 4: Announce selection

Before spawning agents, tell the user and name the detected platform, since it picked the agent set:
```
Platform: Android (MVP)
Classifier selected: [android-review, android-a11y, code-quality] based on: *Fragment.kt + *Presenter.kt changed
Spawning N agents in parallel...
```

### Step 5: Handle agent failures (graceful degrade)

An agent can die before producing findings: a model-key 401, rate limit, or other infra error returns no result. This is **not** a clean review: a skipped agent is missing coverage, not absence of findings. Never let a dead agent pass silently as if its axis were clean.

For every selected agent that did not return findings:

1. **Surface it** in synthesis as `[WARNING] <agent> skipped: <reason>, coverage gap on <axis>`.
2. **List it as skipped** in the `Agents:` line, not as ran.
3. **Gate the verdict.** If a review/build agent (not a fast Bash gate) was skipped by infra, the verdict is `INCOMPLETE`, never `READY TO MERGE` / `DONE`. State which axis is unverified so the user can re-run or accept the gap.

Do not retry a dead model spawn inline, because the model key won't change mid-turn. Report, and if the failing agent has a `model:` override that differs from peers (e.g. `haiku` vs `sonnet`), name that override as the likely cause.

---

