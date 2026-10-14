# craftkit `v1.59.0`

[![npm](https://img.shields.io/npm/v/@raditia/craftkit)](https://www.npmjs.com/package/@raditia/craftkit)
[![npm downloads](https://img.shields.io/npm/dw/@raditia/craftkit)](https://www.npmjs.com/package/@raditia/craftkit)
[![Content integrity](https://github.com/raditia/CraftKit/actions/workflows/check.yml/badge.svg)](https://github.com/raditia/CraftKit/actions/workflows/check.yml)
[![Release](https://img.shields.io/github/v/release/raditia/CraftKit)](https://github.com/raditia/CraftKit/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**One install. A shared way to build across Claude Code, Cursor, Gemini CLI and Codex CLI.**

CraftKit distributes coding rules, skills, workflows and specialist agents from one repository. Git installs sync updates automatically when you pull.

[Website](https://raditia.github.io/CraftKit/) · [Detailed guide](docs/guide.md) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

## Start here

| I want to… | Go to |
|---|---|
| Get CraftKit running | [Install](#install) |
| Build, review or ship a change | [Using the workflows](#using-the-workflows) |
| Understand the system | [How it works](#how-it-works) |
| Find a specific skill or agent | [Skills](#skills-reference) · [Agents](#agents-reference) |
| Configure gates or optional tools | [Configuration](#configuration-extras-and-gate-groups) |
| Maintain CraftKit itself | [Managing skills](#managing-skills) |

## Install

**npm**, with version pinning and rollback:

```bash
npm install -g @raditia/craftkit
```

**Git**, with automatic sync on pull:

```bash
git clone git@github.com:raditia/craftkit.git ~/craftkit
cd ~/craftkit
bash install.sh
```

Requires Bash 3.2+ and curl, plus npm or Git for your chosen method. In Codex, review and trust the installed hooks with `/hooks`.

### Configuration: extras and gate groups

Run `bash sync.sh --configure` from a Git checkout to select optional extras and gate groups. Choices live in `~/.craftkit-state/config` and survive updates.

| Setting | Default | Purpose |
|---|---|---|
| `humanizer` | on | Natural writing for docs and PR messages |
| `playwright` | off | Browser automation CLI and skills |
| `dashboard` | off | Live Claude and Codex agent dashboard |
| `gates.routing` | on | Skill routing and announcement gates |
| `gates.director` | Claude on, Codex off | Delegate larger source edits |
| `gates.verify` | on | Require verification before completion |

For environment overrides, ownership and removal behavior, see the [configuration reference](docs/guide.md#configuration-extras-and-gate-groups).

## How it works

![Repository content passes through sync.sh to Claude Code, Cursor, Gemini CLI and Codex CLI through independent adapters.](docs/diagrams/sync-engine.svg)

| Source | Purpose |
|---|---|
| `rules/` | Standards loaded every session |
| `skills/` | One job, invoked on demand |
| `commands/` | Workflows that coordinate skills and agents |
| `agents/` | Specialist profiles for Claude and Codex |
| `partials/` | Shared instructions injected into their hosts |

### At runtime: Gateway, Orchestrators, state

Claude and Codex use hooks for routing and verification. Cursor and Gemini receive advisory rules. Workflows coordinate skills and agents; per-feature intent and test cases stay in the repository.

[Runtime map](docs/guide.md#at-runtime-gateway-orchestrators-state) · [Editable diagram source](docs/diagrams/runtime.html)

### Where files land per AI tool

| Tool | Rules | Skills and workflows | Specialist agents |
|---|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/commands/` and shared skills | `~/.claude/agents/*.md` |
| Cursor | `~/.cursor/rules/` | `~/.agents/skills/`, local sessions | None installed |
| Gemini CLI | `~/GEMINI.md` | Managed block and shared skills | None installed |
| Codex CLI | SessionStart loads `~/.craftkit/codex/rules/` | `~/.agents/skills/` | `${CODEX_HOME:-~/.codex}/agents/*.toml` |

See [installation details and collision handling](docs/guide.md#where-files-land-per-ai-tool).

## Using the workflows

### Just say what you want

| Ask | Workflow | Result |
|---|---|---|
| “Plan this feature” | `/define` | Reviewed spec, approved test cases and task plan |
| “Build this feature” | `/parallel-build` | Implementation, specialist review and checks |
| “Review my changes” | `/parallel-review` | Findings ranked by evidence and severity |
| “Prepare this for PR” | `/parallel-ship` | Verification and a readiness verdict |
| “Fix this bug” | `/fix` | Reproduction, fix and regression check |
| “Write tests” | `/fe-test`, `/android-test`, `/ios-test` | Tests for the detected platform |
| “Generate a PR message” | `/pr-message` | Description grounded in the branch changes |

The routing hook uses the nearest project markers to detect RN/web, Android, iOS or Node/tooling. [Routing diagram](docs/diagrams/platform-routing.svg)

### Dynamic workflows (default)

![Fast checks pass before read-only specialists review alongside test authoring; the main agent combines findings, fixes errors and runs tests before reporting.](docs/diagrams/parallel-build.svg)

The classifier selects specialists from the actual change. Reviews run independently; the main agent collects every result and reports missing reviews as coverage gaps.

[Build](docs/guide.md#parallel-build) · [Review](docs/guide.md#parallel-review) · [Ship](docs/guide.md#parallel-ship) · [How findings become one verdict](docs/guide.md#how-findings-become-one-verdict)

### Planning pipeline: /define, before you build

![Interview, spec, approved test cases and task planning lead to a separate build request, with approval checkpoints between phases.](docs/diagrams/planning.svg)

At each checkpoint you can continue, edit or stop. `/define` stops at the plan. Ideation and a plan roast are optional.

[Planning reference](docs/guide.md#planning-pipeline-define-before-you-build)

### Enforcement gates: hooks that refuse

Claude and Codex can require verification before a task ends. Some gates are configurable; Cursor and Gemini rely on advisory guidance. Codex verification enforces successful checks against unchanged snapshots, but cannot prove native skill activation.

<details>
<summary>Hook reference and enforcement details</summary>

| Hook | Event | What it does |
|------|-------|--------------|
| [`craftkit-routing.js`](hooks/craftkit-routing.js) | `UserPromptSubmit` | Injects the routing table, platform, model tiers, and any locally installed skills. Advisory |
| [`gate-skill-first.js`](hooks/gate-skill-first.js) | `PreToolUse` on `Edit\|Write\|MultiEdit\|NotebookEdit` | Asks before a source edit in a session that never invoked a skill, naming the skills that fit the file. Once per turn |
| [`gate-delegate.js`](hooks/gate-delegate.js) | `PreToolUse` on `Edit\|Write\|MultiEdit\|NotebookEdit\|Bash` | Asks on the 3rd distinct source file a main-session turn edits and on every source edit after it (shell writes such as `sed -i` count; parallel calls count through its own per-turn record), telling the agent to hand the work to a background agent with a verify contract (director mode). Passes subagents, notifications, planning docs, unattended sessions (`claude -p`, where an ask is auto-denied), and any turn that has handed the work to an agent (a background spawn, or one whose profile can edit; a foreground `Explore` or read-only reviewer does not count). Counts only `.ts/.tsx/.js/.jsx/.mjs/.cjs/.kt/.java/.swift/.m/.mm`, so `.py` and notebooks (`.ipynb`) are not gated. `CRAFTKIT_DELEGATE=off` turns it off |
| [`gate-verify-on-stop.js`](hooks/gate-verify-on-stop.js) | `Stop` | Blocks a turn that edited source but ran no verification command, and names the command (`check.sh` if present, else typecheck + lint). On a background-agent notification turn it counts files dirtied since that agent spawned, ignoring agent worktree dirs, and passes when the agent's own transcript (`<session>/subagents/agent-<task-id>.jsonl`) shows the verify command succeeding after its last write. Edits outside the repo root do not count |
| [`gate-announce-honored.js`](hooks/gate-announce-honored.js) | `Stop` | Blocks a reply that says `Running /<skill>` with no `Skill` call, or carries no routing declaration at all |
| [`gate-read-size.js`](hooks/gate-read-size.js) | `PreToolUse` on `Read` | Refuses a whole-file read over 800 lines and points to the `bulk-read` agent or an `offset`/`limit` read. Denies rather than asks |
| [`craftkit-platform-rules.js`](hooks/craftkit-platform-rules.js) | `SessionStart` | Loads `platform:`-scoped rules only where the cwd matches, so EVPMR laws stay out of Kotlin and Swift sessions |
| [`craftkit-update-check.js`](hooks/craftkit-update-check.js) | `SessionStart` | Tells you when a newer craftkit is on npm. Asks the registry at most once a day (1.5s timeout, cached in `~/.craftkit-state/update-check`) and stays silent on any failure |
| [`craftkit-read-cap.js`](hooks/craftkit-read-cap.js) | `PreToolUse` on `Bash` | Rewrites a bare `cat F` / `rtk read F` over 800 lines to `rtk read -m 800`. Leaves piped commands alone |

[Shared helpers](hooks/craftkit-transcript.js): `craftkit-transcript.js`, `craftkit-platform.js`, `craftkit-filesize.js` and `craftkit-drift.js`.

[Codex hook runner](hooks/craftkit-codex.js) · [Gate behavior, trust and escape hatches](docs/guide.md#enforcement-gates-hooks-that-refuse)

</details>

### Agent dashboard (opt-in)

Enable `dashboard=on` through configuration, then run `ccdash` to watch Claude and Codex sessions and their agents.

<details>
<summary>Dashboard components</summary>

| Piece | Where | What it does |
|-------|-------|--------------|
| [`craftkit-agent-log.js`](hooks/craftkit-agent-log.js) | Claude and Codex, on `SubagentStart`, `SubagentStop`, `PostToolUse`, `SessionEnd` | Appends one line per event to the session's log and keeps a file per running subagent, deleted when it stops and cleared when the session ends. Fails open. Codex needs a one-time `/hooks` trust |
| [`craftkit-statusline.js`](hooks/craftkit-statusline.js) | Claude `statusLine` | Shows model, effort, context, cost and running subagents, and saves them for the dashboard. If you already have a status line it is kept: saved to `~/.craftkit-state/statusline.json`, run first with the same input, and this is appended after it. Turning the dashboard off puts yours back exactly |
| [`scripts/dashboard.py`](scripts/dashboard.py), [`scripts/ccdash`](scripts/ccdash) | `~/.craftkit/bin`, linked into `~/.local/bin` when that exists | The viewer and its launcher. `ccdash` opens a tmux popup inside tmux (a side pane before tmux 3.2), a separate iTerm or Terminal window when run from a chat (`! ccdash`, macOS), or full screen in a plain terminal. Without a terminal it prints one snapshot |

[Setup, controls and runtime limitations](docs/guide.md#agent-dashboard-opt-in)

</details>

### How the classifier picks agents

Views add accessibility review; state and fetching can add performance review; larger changes can add adversarial review. Test-only changes run gates without deep review.

[Selection rules and examples](docs/guide.md#how-the-classifier-picks-agents)

### Sequential fallback

When spawning is unavailable, workflows use `/build`, `/review` or `/ship` and name the lost validation axis. [Fallback diagram](docs/diagrams/fallback.svg)

### Experimental: /team-build, agent teams

Explicit opt-in for Claude Code's experimental teams. Implementers own separate files, then a reviewer and tester start in stages. [Requirements and tradeoffs](docs/guide.md#experimental-team-build-agent-teams)

### Cross-model: /cross-review

An explicit Claude + Codex panel: independent reviews, one peer critique and evidence-based synthesis. Both CLIs and a project auth allowlist are required. [Panel workflow and coverage limits](docs/guide.md#cross-model-cross-review)

### Fix, tests, and PR message

Use `/fix` for broken behavior, the platform test skill for test authoring, and `/pr-message` for a branch-based PR description. [Reference](docs/guide.md#fix-tests-and-pr-message)

### Grill, research, and handoff

Use `/grill` to challenge an existing plan, `/research` for a cited investigation, `/handoff` to preserve session state, and `/context-source` to connect team docs. [Choosing the right tool](docs/guide.md#grill-research-and-handoff)

### Scoring a run: /eval

`/eval` judges the finished result, recomputes its weighted score and records it in `docs/evals/ledger.md`. Missing evidence is reported as a gap; a high total cannot hide a failed criterion.

<details>
<summary>Scoring weights and verdict rules</summary>

| Criterion | Weight | Scored on |
|---|---:|---|
| Spec conformance | 35 | Every PLANNING acceptance criterion actually implemented |
| Correctness | 25 | Edge cases, error paths, no crash or data-loss path |
| Pattern adherence | 20 | EVPMR / MVP / MVVM-C contract holds |
| Verification | 15 | Tests cover changed paths and pass; type + lint clean |
| Simplicity | 5 | Ponytail rubric: nothing to delete |

[Score calculation, floors and thresholds](docs/guide.md#scoring-a-run-eval)

</details>

## Skills reference

<details>
<summary>Browse rules and skills by platform and purpose</summary>

### Always-active rules

Loaded automatically on every session. Never invoke these; they're always present.

| Rule | Enforces |
|------|---------|
| [`fe-rules`](rules/fe-rules.md) | EVPMR layer constraints, TypeScript strict, module-over-barrel imports, styling tokens, React correctness, tracking |
| [`flag-safety`](rules/flag-safety.md) | Flag OFF stays behavior-identical: code paths, persisted state, API contracts, analytics. `flag:` marker, both states tested |
| [`grounding`](rules/grounding.md) | Claims that drive action carry provenance: `[verified: how]`, `[from context.md @sha]`, `[UNVERIFIED]`. An `[UNVERIFIED]` claim cannot back an `[ERROR]` finding or an edit. Cold agents review handed content only; staleness reports cannot-verify, never clean |
| [`karpathy-guidelines`](rules/karpathy-guidelines.md) | Think before coding, simplicity, surgical changes, goal-driven, read before write, tests verify intent, checkpoint after steps |
| [`using-agent-skills`](rules/using-agent-skills.md) | Skill routing (mandatory gate: classify before every response, announce match or "No skill matched."), model selection, severity labels, parallel classifier, model for judgment only, surface conflicts, director mode (12a: assess first; quick work of up to two files stays direct, long-running, 3+ file or parallel work goes to background agents, and every turn reaps finished or stalled agents via `ListAgents` + `TaskStop`, Claude Code only) |

### Frontend skills, on demand

Use when a task is narrower than a full workflow.

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`fe-context`](skills/fe-context/SKILL.md) | Derive the branch's change context from the diff, emitted into the turn, no file written | Diff spans > 10 interdependent files |
| [`fe-scaffold`](skills/fe-scaffold/SKILL.md) | Create a new 5-file EVPMR module | Novel architecture outside EVPMR |
| [`fe-review`](skills/fe-review/SKILL.md) | EVPMR pattern review only | Architectural conflicts with non-obvious resolution |
| [`fe-patterns`](skills/fe-patterns/SKILL.md) | Props drilling, shared state placement (Context in Model, provider in Entry), composition patterns, hooks discipline | Novel state architecture |
| [`fe-performance`](skills/fe-performance/SKILL.md) | Waterfall elimination, bundle size, re-renders | Lighthouse regressions with non-obvious root cause |
| [`fe-a11y`](skills/fe-a11y/SKILL.md) | Labels, roles, focus management, reduced motion, for RN & Next.js | Complex focus flows spanning multiple routes |
| [`fe-design`](skills/fe-design/SKILL.md) | Visual design that reads as AI-generated: default gradients and glass, template layouts, decorative filler, invented dashboard numbers, responsive breaks. Adapted from [anti-slop](https://github.com/miqdadbadjuber/anti-slop) (MIT) | Whether a technique earns its place is contested |
| [`fe-test`](skills/fe-test/SKILL.md) | Write/improve tests, enforcing ≥93% coverage. **RN/web only**, since native goes to `/android-test` / `/ios-test` | Can't reach 93%, root cause unclear |

### Native mobile skills, on demand

Native mobile does **not** use EVPMR. For single-screen work, read a real sibling screen instead of deriving context. For concrete module names, add a project override at `<repo>/.claude/skills/<name>/`; the same name shadows the global skill inside that repo.

The `*-review`, `*-a11y` and `*-performance` skills are also the live source for the matching cold agents (via `craftkitInject`), so editing the skill updates the agent on the next sync.

**Android:** MVP + Core framework, Dagger, Gradle Dynamic Feature Modules:

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`android-patterns`](skills/android-patterns/SKILL.md) | Architecture reference: MVP layers, DI, module split, navigation | Novel state/effect orchestration |
| [`android-scaffold`](skills/android-scaffold/SKILL.md) | Scaffold a new screen (View/Presenter/ViewModel + Dagger wiring) | Outside the Core MVP contract |
| [`android-review`](skills/android-review/SKILL.md) | Review a diff against the MVP contract | Architectural conflict, non-obvious resolution |
| [`android-a11y`](skills/android-a11y/SKILL.md) | TalkBack labels/state, touch targets, Compose semantics | Complex focus flows across screens |
| [`android-performance`](skills/android-performance/SKILL.md) | Main-thread/coroutine, RecyclerView, recomposition, leaks | Jank/leak with non-obvious root cause |
| [`android-test`](skills/android-test/SKILL.md) | JUnit + MockK Presenter tests (Turbine for Flow) | Path unreachable without production refactor |
| [`android-context`](skills/android-context/SKILL.md) | Branch-scoping doc for multi-screen work | Multi-module cross-feature `-api` changes |

**iOS:** MVVM-C, Bazel + CocoaPods, Quick + Nimble:

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`ios-patterns`](skills/ios-patterns/SKILL.md) | Architecture reference: MVVM-C, Fetcher, Coordinator, Dependency-struct DI | Novel state/effect orchestration |
| [`ios-scaffold`](skills/ios-scaffold/SKILL.md) | Scaffold a new screen (Contract/VC/View/ViewModel/Factory/Fetcher) | Outside the MVVM-C contract |
| [`ios-review`](skills/ios-review/SKILL.md) | Review a diff against the MVVM-C contract | Architectural conflict, non-obvious resolution |
| [`ios-a11y`](skills/ios-a11y/SKILL.md) | VoiceOver labels/traits, focus, Dynamic Type, reduce motion | Complex focus flows across screens |
| [`ios-performance`](skills/ios-performance/SKILL.md) | Main-thread, cell reuse, image downsampling, retain-cycle leaks | Jank/leak with non-obvious root cause |
| [`ios-test`](skills/ios-test/SKILL.md) | Quick + Nimble ViewModel specs, mock via Dependency struct | Path unreachable without production refactor |
| [`ios-context`](skills/ios-context/SKILL.md) | Branch-scoping doc for multi-screen work | Multi-module cross-module coordinator changes |

### General skills, on demand

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`code-quality`](skills/code-quality/SKILL.md) | Review (5-axis) or simplify complex code | Security-sensitive review, or refactor > 500 lines |
| [`debug`](skills/debug/SKILL.md) | Structured reproduce → isolate → fix | No hypothesis after 2 isolation attempts |
| [`ideate`](skills/ideate/SKILL.md) | Divergent ideation: N framed generators → critic scores/clusters. Open-ended design, naming, fuzzy debug | High-stakes, so escalate the critic/deepen pass to opus |
| [`think`](skills/think/SKILL.md) | Systems/strategy reasoning router: cynefin, systems, feedback loops, constraints, leverage, second-order. Architecture + complex-system decisions | Architecture call with non-obvious tradeoffs, so escalate analysis to opus |
| [`research`](skills/research/SKILL.md) | Background agent researches a question against primary sources only, writes a cited note into the repo | n/a |
| [`handoff`](skills/handoff/SKILL.md) | Compact the session into a handoff doc for a fresh agent: state, decisions, next steps, suggested skills | n/a |
| [`context-source`](skills/context-source/SKILL.md) | Connect, replace, disconnect or list the team docs repos on GitHub that `/interview`, `/spec` and `/plan` check asks against, with cited conflicts. Cache under `~/.craftkit`, never in the project (ADR-0003) | n/a |
| [`eval`](skills/eval/SKILL.md) | Score a finished run into a weighted correctness %: spawns `eval-judge`, appends `docs/evals/ledger.md`, derives the success rate | Score gates a merge or release, so escalate the judge; irreversible gate, so run a fusion panel of two judges |
| [`ponytail-review`](skills/ponytail-review/SKILL.md) | Over-engineering audit on a diff or file: what to delete/shrink | Correctness or security concerns → use `code-quality` |
| [`ponytail-audit`](skills/ponytail-audit/SKILL.md) | Whole-repo bloat scan: ranked list of removals | n/a |
| [`ponytail-debt`](skills/ponytail-debt/SKILL.md) | Ledger of every `ponytail:` shortcut and `flag:` branch, surfacing deferred simplifications and removable flags | n/a |

### Planning & docs skills, on demand

All opt-in, never auto-run from `/parallel-build`. `/spec`, `/plan` and `/adr` write the feature's intent file at `docs/planning/<slug>.md`. How they chain: [Planning pipeline](#planning-pipeline-define-before-you-build).

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`interview`](skills/interview/SKILL.md) | De-fuzz an underspecified ask: one question at a time to ~95% confidence, then hand to `/spec` | n/a |
| [`spec`](skills/spec/SKILL.md) | Write a PRD before coding: objective, scope, boundaries, acceptance criteria | Hard-to-reverse (schema, public API, payment/auth), so escalate to opus |
| [`test-cases`](skills/test-cases/SKILL.md) | QA test-case documents (title, steps, expected) from the feature's Figma and Lark sources into `docs/planning/<slug>.tests.md`; you approve rows, it re-reviews on source drift and exports Excel. Test code stays with `/fe-test`, `/android-test`, `/ios-test` | Sources contradict each other, so escalate to opus |
| [`plan`](skills/plan/SKILL.md) | Break a spec into ordered, verifiable tasks + deps + executing skill; offers `plan-roaster` | Large dependency graph or > 5 interdependent files |
| [`adr`](skills/adr/SKILL.md) | Record one architectural decision: context, options, decision, consequences (the *why*) | n/a |
| [`grill`](skills/grill/SKILL.md) | Stress-test an existing plan/decision: frontier-round interview until nothing is silently assumed; parks ungrillable questions, captures `docs/glossary.md` terms, offers `/adr` | n/a |
| [`docs`](skills/docs/SKILL.md) | Dual-audience docs: technical (engineers) + non-technical (stakeholders), Confluence-paste-ready markdown, run through `/humanizer` | Accuracy depends on subtle system behavior, so escalate to everyday |

</details>

## Agents reference

Read-only specialists install for Claude Code and Codex. Codex profiles inherit the configured model with medium reasoning effort.

<details>
<summary>Browse specialist agents</summary>

| Agent | Platform | Role | Spawned by | Model |
|-------|----------|------|-----------|-------|
| [`code-quality`](agents/code-quality.md) | all | 5-axis review: correctness, readability, arch, security, performance | `parallel-review`, `parallel-ship` | sonnet |
| [`ponytail-review`](agents/ponytail-review.md) | all | Over-engineering: reinvented stdlib, speculative abstraction, dead flexibility (complexity only) | `parallel-build`, `parallel-ship` | sonnet |
| [`bulk-read`](agents/bulk-read.md) | all | Single-shot file reader: answers one question about large files as `file:line` bullets, so the file never enters the caller's context | `gate-read-size.js` (offered on an `ask`) | sonnet |
| [`adversarial`](agents/adversarial.md) | all | Devil's advocate: strongest case against merging/shipping | `parallel-review`, `parallel-build`, `parallel-ship` | sonnet |
| [`fe-review`](agents/fe-review.md) | RN / web | EVPMR layer violations, TypeScript, styling, React correctness, tracking | `parallel-review`, `parallel-build`, `parallel-ship` | sonnet |
| [`fe-a11y`](agents/fe-a11y.md) | RN / web | Accessibility: labels, roles, focus, announcements, reduced motion | `parallel-review`, `parallel-build`, `parallel-ship` | sonnet |
| [`fe-patterns`](agents/fe-patterns.md) | RN / web | Props drilling past 3 levels, state location, hooks discipline, composition patterns | `parallel-build` | sonnet |
| [`fe-performance`](agents/fe-performance.md) | RN / web | Waterfalls, bundle size, re-renders, server-side, RN patterns | `parallel-build`, `parallel-ship` | sonnet |
| [`android-review`](agents/android-review.md) | Android | MVP layer violations, Dagger DI, NavigatorService nav, string resources, coroutine correctness | `parallel-review`, `parallel-build`, `parallel-ship` | sonnet |
| [`android-a11y`](agents/android-a11y.md) | Android | TalkBack labels, roles/state, touch targets, focus order, text scaling | `parallel-review`, `parallel-build`, `parallel-ship` | sonnet |
| [`android-performance`](agents/android-performance.md) | Android | Main-thread discipline, RecyclerView/DiffUtil, recomposition stability, image loading, leaks | `parallel-build`, `parallel-ship` | sonnet |
| [`ios-review`](agents/ios-review.md) | iOS | MVVM-C layer violations, Dependency-struct DI, Coordinator-only nav, NSLocalizedString, retain cycles | `parallel-review`, `parallel-build`, `parallel-ship` | sonnet |
| [`ios-a11y`](agents/ios-a11y.md) | iOS | VoiceOver labels/traits/hints, focus & announcements, Dynamic Type, reduce motion | `parallel-review`, `parallel-build`, `parallel-ship` | sonnet |
| [`ios-performance`](agents/ios-performance.md) | iOS | Main-thread discipline, cell reuse & prefetch, image downsampling, layout cost, retain cycles | `parallel-build`, `parallel-ship` | sonnet |
| [`plan-roaster`](agents/plan-roaster.md) | all | Stress-test a plan before implementation: weakest assumption + failure modes | On demand | sonnet |
| [`eval-judge`](agents/eval-judge.md) | all | Weighted correctness scoring of a finished deliverable: five criteria at 0-5, floors, verdict | `/eval`, offered by `parallel-build` + `parallel-ship` | sonnet |

</details>

### Skill vs agent: when to add which

A skill handles work you invoke directly or that needs conversation history. An agent handles isolated work spawned by an orchestrator. Use both when you need both entry points. [Authoring reference](docs/guide.md#managing-skills)

## Architecture (EVPMR)

Frontend features use Entry, View, Presenter, Model and Resource roles. Android uses MVP; iOS uses MVVM-C. [Frontend architecture diagram](docs/diagrams/evpmr.svg) · [Rules and examples](docs/guide.md#architecture-evpmr)

### How context flows between skills

Git context is derived into the turn. Human intent lives in `docs/planning/<slug>.md`; approved cases live in its `.tests.md` sibling. [Context diagram and resolver contracts](docs/guide.md#how-context-flows-between-skills)

## Model routing

Skills name tiers rather than pinned model IDs. Claude derives tiers from account data; Gemini uses CLI aliases; Codex inherits its configured model and changes reasoning effort; Cursor stays picker-controlled.

[Model selection diagrams and escalation rules](docs/guide.md#model-routing)

## Managing skills

Edit source files here. `sync.sh` generates installed copies. Follow the [authoring checklist](CLAUDE.md#critical-authoring-rules) and [contribution guide](CONTRIBUTING.md).

```bash
bash check.sh
bash sync.sh
bash sync.sh
```

The checks must pass, the first sync must succeed, and the second must report everything up to date. [Adding and removing content](docs/guide.md#managing-skills)

## Why bother?

Keep the same coding standards when you switch AI tools. Load a skill when its job fits the task; use specialist reviews and project checks before claiming completion.

## Tooling

| Tool | Purpose |
|---|---|
| RTK | Filter shell output before the agent reads it |
| Caveman | Shorten agent responses |
| Ponytail / Karpathy guidelines | Prefer simple code and delete unnecessary complexity |
| Diagram Design | Editorial diagrams with editable HTML sources and SVG embeds |

[Design decisions](docs/design-notes.md) · [Diagram inventory and maintenance](docs/diagrams/README.md)
