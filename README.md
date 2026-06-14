# agentic-skills `v1.2.0`

One repo of AI coding skills that auto-syncs across **Claude Code**, **Cursor**, **GitHub Copilot**, and **Gemini CLI**. Pull once — every AI tool gets the same workflows, rules, and commands.

---

## Table of contents

- [Why bother?](#why-bother) — token savings with RTK + Caveman
- [Install](#install)
- [How it works](#how-it-works)
- [Using the workflows](#using-the-workflows)
  - [Just say what you want](#just-say-what-you-want)
  - [Dynamic workflows](#dynamic-workflows-default) — `/parallel-review`, `/parallel-ship`, `/parallel-build`
  - [How the classifier picks agents](#how-the-classifier-picks-agents)
  - [Sequential fallback](#sequential-fallback) — `/review`, `/ship`, `/build`
  - [Fix, tests, and PR message](#fix-tests-and-pr-message)
- [Skills reference](#skills-reference)
- [Architecture (EVPMR)](#architecture-evpmr)
- [Model routing](#model-routing)
- [Managing skills](#managing-skills)
- [Changelog](#changelog)

---

## Why bother?

AI coding sessions are expensive. Two things drain tokens fast: **verbose shell output** the AI has to read, and **verbose AI responses** you have to read. This repo ships two compression layers that cut both.

### RTK — compresses what the AI reads (shell output)

Shell commands like `git diff` and `jest` dump noise before the signal. RTK filters it out before it reaches the AI.

```
── WITHOUT RTK (38 tokens) ──────────────────────────────────────────
On branch feature/checkout-flow
Your branch is ahead of 'origin/feature/checkout-flow' by 3 commits.
  (use "git push" to publish your local commits)

Changes not staged for commit:
  (use "git add <file>..." to update staging area)

        modified:   src/checkout/ViewCheckout.tsx
        modified:   src/checkout/PresenterCheckout.ts

Untracked files:
        src/checkout/__tests__/ViewCheckout.test.tsx

── WITH RTK (6 tokens) ──────────────────────────────────────────────
M src/checkout/ViewCheckout.tsx
M src/checkout/PresenterCheckout.ts
? src/checkout/__tests__/ViewCheckout.test.tsx
```

**~84% reduction** on a single call. Across a full session — `git diff`, `tsc`, `jest`, `lint` — compounds to **60–90% savings on AI input tokens**.

### Caveman — compresses what you read (AI output)

The `caveman` rule strips filler, hedging, and pleasantries from every response. Same findings, fewer words.

```
── WITHOUT CAVEMAN (~65 tokens) ─────────────────────────────────────
Sure! After carefully reviewing the code, I can see that there's
actually an issue in the ViewCheckout component. It looks like
there's a useState hook being used directly in the View layer,
which basically violates the EVPMR architecture pattern. You'll
want to move that state logic into the Presenter layer instead.

── WITH CAVEMAN (~18 tokens) ────────────────────────────────────────
[ERROR] ViewCheckout.tsx:14 — useState in View layer.
  Why: violates EVPMR.
  Fix: move to PresenterCheckout.ts.
```

**~72% reduction** per response. Full review sessions with reasoning and multi-step output: **40–60% output savings**.

### Combined impact

| Layer | Compresses | Typical savings |
|-------|------------|-----------------|
| RTK | Shell output → AI input | 60–90% on dev operations |
| Caveman | AI output → your reading | 40–60% on prose responses |
| **Together** | Both directions | **50–80% total session cost** |

Typical feature review session without compression: ~40,000 tokens. With RTK + Caveman: ~8,000–20,000 tokens.

---

## Install

```bash
git clone git@github.com:raditia/agentic-skills.git ~/agentic-skills
cd ~/agentic-skills
bash install.sh
```

`install.sh` wires up the post-merge hook and runs the first sync. After that, `git pull` keeps every AI tool up to date automatically.

**Requirements:** bash 3.2+, curl. macOS ships bash 3.2 by default.  
**Optional:** `jq` for Copilot VS Code settings integration.

**Per-project Copilot `@` agents** (run inside any project repo):
```bash
bash ~/agentic-skills/scripts/init-copilot-agents.sh
# commit .github/ to share with your team
```

---

## How it works

Every `git pull` triggers a sync that installs rules and skills into each AI tool:

```
git pull
   │
   └─► post-merge hook
           │
           └─► sync.sh
                   │
                   ├─► RTK + Caveman          (token compression tools)
                   ├─► rules/*.md             → always-on rules (every session)
                   ├─► skills/*/SKILL.md      → on-demand slash commands
                   └─► commands/*.md          → on-demand workflow orchestrators
```

Three namespaces, one source of truth:

| Directory | Loaded | Invoked |
|-----------|--------|---------|
| `rules/` | Every session, automatically | Never — always present |
| `skills/` | On demand | Slash command or natural language |
| `commands/` | On demand | Slash command or natural language |

### Where files land per AI tool

```
rules/  →  ALWAYS-ON
┌──────────────┬────────────────────────────────────────┐
│ Claude Code  │ ~/.claude/CLAUDE.md    (managed block) │
│ Cursor       │ ~/.cursor/rules/*.mdc  (alwaysApply)   │
│ Copilot      │ codeGeneration.instructions            │
│ Gemini CLI   │ ~/GEMINI.md            (managed block) │
└──────────────┴────────────────────────────────────────┘

skills/ and commands/  →  ON-DEMAND
┌──────────────┬────────────────────────────────────────┐
│ Claude Code  │ ~/.claude/commands/<name>.md → /<name> │
│ Cursor       │ ~/.cursor/rules/*.mdc  (alwaysApply:f) │
│ Copilot      │ codeGeneration.instructions            │
│ Gemini CLI   │ ~/GEMINI.md            (managed block) │
└──────────────┴────────────────────────────────────────┘
```

---

## Using the workflows

### Just say what you want

Natural language routes to the right command automatically. No slash commands required.

```
"review this"           →  /parallel-review
"build this feature"    →  /parallel-build
"ship this"             →  /parallel-ship
"fix this bug"          →  /fix
"write tests for this"  →  /fe-test
"generate PR message"   →  /pr-message
```

---

### Dynamic workflows (default)

Build, review, and ship use **dynamic parallel execution** — a classifier reads your actual diff, selects only the agents that matter, and runs them concurrently. Test-only diffs skip deep review entirely.

#### /parallel-review

```
"review this" / "help me review" / "code review" / "LGTM check"
                          │
                          ▼
               ┌──────────────────┐
               │ /parallel-review │
               └────────┬─────────┘
                        │
            ┌───────────▼───────────┐
            │       Phase 1         │  parallel — fast gates
            │  ─────────────────── │
            │  tsc  ‖  lint  ‖  test│
            └───────────┬───────────┘
                        │ all pass ✓
                        ▼
            ┌───────────────────────┐
            │   classify diff       │  reads actual files
            │   select agents       │  skips irrelevant ones
            └───────────┬───────────┘
                        │
            ┌───────────▼──────────────────────────┐
            │              Phase 2                  │  parallel — LLM agents
            │  ─────────────────────────────────── │
            │  code-quality  ‖  fe-review  ‖  ...  │  selected by classifier
            └───────────┬──────────────────────────┘
                        │
                        ▼
            ┌───────────────────────┐
            │      synthesize       │  merge + deduplicate
            └───────────┬───────────┘
                        ▼
                  merged report
```

#### /parallel-ship

```
"ship this" / "prepare for PR" / "is this ready?" / "get this ready to merge"
                          │
                          ▼
               ┌─────────────────┐
               │ /parallel-ship  │
               └───────┬─────────┘
                       │
           ┌───────────▼────────────────┐
           │          Phase 1           │  parallel — with coverage gate
           │  ────────────────────────  │
           │  tsc  ‖  lint  ‖  test+cov │  ≥93% coverage required
           └───────────┬────────────────┘
                       │ all pass ✓
                       ▼
           ┌───────────────────────────┐
           │       classify diff       │
           └───────────┬───────────────┘
                       │
           ┌───────────▼────────────────────────────────────┐
           │                  Phase 2                        │  parallel
           │  ─────────────────────────────────────────────  │
           │  code-quality  ‖  fe-review  ‖  fe-performance? │
           │            ‖  fe-a11y?  ‖  adversarial?         │
           └───────────┬────────────────────────────────────┘
                       │
                       ▼
           ┌───────────────────────┐
           │       synthesize      │
           └───────────┬───────────┘
                       ▼
              READY TO MERGE / BLOCKED
```

#### /parallel-build

```
"build feature X" / "implement X" / "create a new screen" / "scaffold a module"
                          │
                          ▼
               ┌──────────────────┐
               │ /parallel-build  │
               └───────┬──────────┘
                       │
               ┌───────▼──────────┐
               │   fe-context     │  sequential — must happen first
               └───────┬──────────┘
                       │
               ┌───────▼──────────┐
               │   fe-scaffold    │  sequential — creates 5-file module
               └───────┬──────────┘
                       │
               ┌───────▼──────────┐
               │    implement     │  guided by fe-patterns + fe-performance
               └───────┬──────────┘
                       │
           ┌───────────▼───────────┐
           │       Phase 3         │  parallel — fast gates
           │  tsc  ‖  lint         │
           └───────────┬───────────┘
                       │ all pass ✓
                       ▼
           ┌───────────────────────────┐
           │   classify what was built │
           └───────────┬───────────────┘
                       │
           ┌───────────▼────────────────────────────────┐
           │               Phase 5                       │  parallel
           │  fe-review  ‖  fe-patterns  ‖  fe-a11y?    │
           │       ‖  fe-performance?  ‖  adversarial?  │
           └───────────┬────────────────────────────────┘
                       │ no [ERROR]
                       ▼
               ┌───────────────┐
               │    fe-test    │  sequential — write tests, enforce ≥93%
               └───────┬───────┘
                       ▼
                    DONE
```

---

### How the classifier picks agents

The classifier reads your actual changed files — not just filenames — and selects only the agents that apply. Irrelevant agents are skipped entirely.

```
git diff shows:                          agents selected:
──────────────────────────────────────────────────────────
View*.tsx                           →   code-quality + fe-review + fe-a11y
Presenter*.ts                       →   code-quality + fe-review
Model*.ts                           →   code-quality (type/correctness focus)
Entry*.tsx or Resource*.ts          →   fe-review
View or Presenter + /parallel-ship  →   + fe-performance
3+ EVPMR layers changed             →   + adversarial (devil's advocate)
auth / payment / credential paths   →   code-quality (security emphasis)
test files only                     →   Phase 2 SKIPPED entirely
```

**Examples:**

```
── Example A: View + Presenter changed ──────────────────────
diff: ViewCheckout.tsx, PresenterCheckout.ts
           │
    ┌──────▼──────────────┐
    │      classify       │
    └──┬────────┬────┬────┘
       ▼        ▼    ▼
  code-quality  fe-  fe-
               review a11y
       └────────┴────┘
             ▼
         synthesize → merged findings

── Example B: Model only ────────────────────────────────────
diff: ModelCheckout.ts
           │
    ┌──────▼──────────────┐
    │      classify       │
    └──────────┬──────────┘
               ▼
          code-quality
      (type safety focus)
               ▼
      targeted findings
      no EVPMR/a11y noise

── Example C: Test files only ───────────────────────────────
diff: __tests__/ViewCheckout.test.tsx
           │
    ┌──────▼──────────────┐
    │  classify: tests    │
    │  Phase 2 SKIPPED   │  saves LLM agent cost entirely
    └──────────┬──────────┘
               ▼
      Phase 1 only: tsc + lint + test

── Example D: 4 EVPMR layers (adversarial triggered) ───────
diff: Entry + View + Presenter + Model
           │
    ┌──────▼──────────────────┐
    │  3+ layers → adversarial│
    └──┬──────┬──────┬────┬───┘
       ▼      ▼      ▼    ▼
  code-  fe-   fe-  adver-
  quality review a11y sarial
       └──────┴──────┴────┘
                  ▼
         findings + "strongest
         case against merging"
```

---

### Sequential fallback

When you want a lightweight, single-pass run — use the explicit slash command.

| Command | When to prefer |
|---------|---------------|
| [`/review`](commands/review.md) | Quick sanity check, small diff |
| [`/ship`](commands/ship.md) | Simple pre-merge gate, tests already passing |
| [`/build`](commands/build.md) | Scaffold-only, no parallel validation needed |

---

### Fix, tests, and PR message

```
"something is broken" / "fix this bug" / "this crashes"
  /fix  →  fe-context → reproduce → isolate → fix → regression test

"write tests" / "add tests" / "coverage is low"
  /fe-test  →  write tests for all changed paths, enforce ≥93% coverage

"generate PR message" / "draft a PR" / "what should my PR say"
  /pr-message  →  read diff → write summary + goal + changes + coverage → copy to clipboard
```

---

## Skills reference

### Always-active rules

Loaded automatically on every session. Never invoke these — they're always present.

| Rule | Enforces |
|------|---------|
| [`caveman`](rules/caveman.md) | Terse responses — no filler, no hedging. lite / full / ultra modes |
| [`fe-rules`](rules/fe-rules.md) | EVPMR layer constraints, TypeScript strict, styling tokens, React correctness, tracking |
| [`karpathy-guidelines`](rules/karpathy-guidelines.md) | Think before coding, simplicity, surgical changes, goal-driven, read before write, tests verify intent, checkpoint after steps |
| [`using-agent-skills`](rules/using-agent-skills.md) | Skill routing, model selection, severity labels, parallel classifier, model for judgment only, surface conflicts |

### Frontend skills — on demand

Use when a task is narrower than a full workflow.

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`fe-context`](skills/fe-context/SKILL.md) | Generate `docs/context.md` from branch diff | Diff spans > 10 interdependent files |
| [`fe-scaffold`](skills/fe-scaffold/SKILL.md) | Create a new 5-file EVPMR module | Novel architecture outside EVPMR |
| [`fe-review`](skills/fe-review/SKILL.md) | EVPMR pattern review only | Architectural conflicts with non-obvious resolution |
| [`fe-patterns`](skills/fe-patterns/SKILL.md) | Composition patterns, hooks discipline, state location | Novel state architecture |
| [`fe-performance`](skills/fe-performance/SKILL.md) | Waterfall elimination, bundle size, re-renders | Lighthouse regressions with non-obvious root cause |
| [`fe-a11y`](skills/fe-a11y/SKILL.md) | Labels, roles, focus management, reduced motion — RN & Next.js | Complex focus flows spanning multiple routes |
| [`fe-test`](skills/fe-test/SKILL.md) | Write/improve tests — enforces ≥93% coverage | Can't reach 93%, root cause unclear |

### General skills — on demand

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`code-quality`](skills/code-quality/SKILL.md) | Review (5-axis) or simplify complex code | Security-sensitive review, or refactor > 500 lines |
| [`debug`](skills/debug/SKILL.md) | Structured reproduce → isolate → fix | No hypothesis after 2 isolation attempts |

---

## Architecture (EVPMR)

All frontend features follow a strict 5-file module structure. Rules are enforced by `fe-rules` at all times — no invocation needed.

```
feature-name/
├── EntryFeatureName.tsx      ← ErrorBoundary + context providers
├── ViewFeatureName.tsx       ← Pure render — calls usePresenter*, no state/effects
├── PresenterFeatureName.ts   ← All hooks, state, React Query — returns plain object
├── ModelFeatureName.ts       ← TypeScript types + pure functions only
└── ResourceFeatureName.ts    ← All display strings
```

```
View       NEVER  useState / useEffect / API calls
Presenter  NEVER  return JSX
Model      NEVER  import React or cause side effects
Entry      ALWAYS wrap in <ErrorBoundary>
Resource   ALWAYS own display strings — never hardcode in View
Styles     ALWAYS StyleSheet.create() + Token.spacing.* / Token.color.*
```

Async data always as discriminated unions:
```ts
type AsyncData<T> =
  | { type: 'NOT_ASKED' }
  | { type: 'LOADING' }
  | { type: 'DATA_READY'; payload: T }
  | { type: 'ERROR'; error: string }
```

### How context flows between skills

`/fe-context` writes `docs/context.md` (≤ 600 lines). Every skill reads it instead of re-scanning the project — one diff scan, many skills benefit.

```
                    ┌──────────────────┐
                    │   /fe-context    │
                    │  reads diff      │
                    │  writes docs/    │
                    │  context.md      │
                    └────────┬─────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
   ┌─────────────┐   ┌──────────────┐   ┌─────────────┐
   │ /fe-scaffold│   │ /fe-review   │   │  /fe-test   │
   │  5-file     │   │ /fe-patterns │   │  ≥93%       │
   │  EVPMR      │   │ /fe-perf     │   │  coverage   │
   │  module     │   │ /code-quality│   │             │
   └─────────────┘   └──────────────┘   └─────────────┘
```

| Level | Source | What |
|-------|--------|------|
| L1 — Rules | Always-active skill files | EVPMR, tokens, Karpathy guidelines |
| L2 — Spec | `docs/context.md` | What's being built, constraints, decisions |
| L3 — Source | Diff output | Files touched by this branch |
| L4 — Errors | On demand | Failing tests, lint, TypeScript errors |
| L5 — History | Session | Conversation context |

---

## Model routing

Each skill runs on the everyday model. Escalation is inline — the AI consults the higher model for a specific question and continues without interrupting you.

| AI | Everyday | Escalates to |
|----|----------|-------------|
| Claude Code | `claude-sonnet-4-6` | `claude-opus-4-7` |
| Gemini CLI | `gemini-2.5-flash` | `gemini-2.5-pro` |
| Cursor | claude-sonnet / gpt-4o | claude-opus / o1 |
| Copilot | `claude-sonnet-4-6` | `claude-opus-4-7` |

Escalation triggers: architecture decisions with non-obvious tradeoffs, security-sensitive code, debugging with no hypothesis after 2 attempts.

---

## Managing skills

**Never edit installed files directly** in `~/.claude/`, `~/.cursor/`, or VS Code settings — `sync.sh` owns them and will overwrite on next pull. Always edit source files in this repo.

### Add a rule (always-on)

```bash
# 1. create the file
echo '---\nname: my-rule\ndescription: What it enforces\n---\n\n...' > rules/my-rule.md

# 2. ship it
git add rules/my-rule.md && git commit -m "feat: add my-rule" && git push
# users: git pull → auto-installed
```

### Add a skill (on-demand)

```bash
mkdir -p skills/my-skill
# create skills/my-skill/SKILL.md with frontmatter: name, description, alwaysApply: false
git add skills/my-skill && git commit -m "feat: add my-skill" && git push
```

### Add a command (orchestrator)

```bash
# create commands/my-command.md with frontmatter: name, description
git add commands/my-command.md && git commit -m "feat: add my-command" && git push
```

### Remove a skill or command

```bash
git rm -r skills/<name>/       # or: git rm commands/<name>.md
git commit -m "remove: <name>" && git push
# users: git pull → auto-uninstalled from all AI tools
```

---

## Tooling

| Tool | Purpose | Auto-installed |
|------|---------|----------------|
| [RTK](https://github.com/rtk-ai/rtk) | Filters shell output before it reaches the AI — saves 60–90% on input tokens | Yes, on `bash install.sh` |
| Caveman | Strips AI output verbosity — saves 40–60% on response tokens | Yes, via `rules/caveman.md` |

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| `v1.2.0` | 2026-06-14 | Dynamic parallel workflows made default for `/build`, `/review`, `/ship`. README restructured with workflow diagrams, TOC, and token savings examples |
| `v1.1.0` | 2026-06-13 | Added `/parallel-review`, `/parallel-build`, `/parallel-ship` with classifier-based agent selection. Audited and cleaned all skills |
| `v1.0.3` | 2026-06-10 | Added `/pr-message` skill. Enforced `no-unused-vars` in `fe-rules`. Added `tsc --noEmit` verification after any TS change |
| `v1.0.2` | 2026-06-08 | Skill invocation announcements. Fluent tracker mock. Natural language triggers for `/fe-test`. Per-project Copilot agents auto-sync on `git pull` |
| `v1.0.1` | 2026-06-05 | Bash 3.2 support (macOS default). Natural language routing for `/fe-test`. `init-copilot-agents.sh` for per-project `@` agents |
| `v1.0.0` | 2026-06-01 | Three-tier namespace (`rules/`, `skills/`, `commands/`). `code-quality` skill. Inline model escalation. `fe-a11y` skill. Caveman embedded as rule. Skill auto-cleanup on `git pull` |
