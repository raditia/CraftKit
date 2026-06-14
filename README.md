# agentic-skills

Centralized AI coding skills that auto-sync across **Claude Code**, **Cursor**, **GitHub Copilot**, and **Gemini CLI**. One repo, one `git pull` — all your AI tools stay in sync.

---

## How it works

```
git pull
   │
   └─► post-merge hook (.git/hooks/post-merge)
           │
           └─► sync.sh
                   │
                   ├─► ensure_tools()
                   │       ├─► RTK     (token compression for AI input)
                   │       └─► Caveman (token compression for AI output)
                   │
                   ├─► sync_rules_adapter()     ← rules/*.md
                   │       ├─► always installed as always-on rules
                   │       ├─► installs new / updated rules
                   │       └─► removes rules deleted from repo
                   │
                   ├─► sync_adapter()           ← skills/*/SKILL.md
                   │       ├─► installed as on-demand commands
                   │       ├─► installs new / updated skills
                   │       └─► removes skills deleted from repo
                   │
                   ├─► sync_commands_adapter()  ← commands/*.md
                   │       ├─► installed as on-demand commands (workflow orchestrators)
                   │       ├─► installs new / updated commands
                   │       └─► removes commands deleted from repo
                   │
                   └─► finalize_<adapter>()     ← integrity check for managed files
```

Three namespaces — all synced automatically on every `git pull`:

| Directory | Purpose | Invocation |
|-----------|---------|------------|
| `rules/` | Always-on behavioral rules and constraints | Never — auto-loaded every session |
| `skills/` | Specific, single-purpose capabilities | On-demand (slash command or natural language) |
| `commands/` | Workflow orchestrators that chain multiple skills | On-demand (slash command or natural language) |

---

## Token savings

Two compression layers work together — one on AI input, one on AI output.

### RTK — compresses AI input (shell command output)

Shell commands like `git diff` and `jest` produce verbose output full of noise. RTK filters it before it reaches the AI — fewer input tokens per operation.

**`git status` — before vs after RTK:**

```
── WITHOUT RTK (38 tokens) ──────────────────────────────────────────
On branch feature/checkout-flow
Your branch is ahead of 'origin/feature/checkout-flow' by 3 commits.
  (use "git push" to publish your local commits)

Changes not staged for commit:
  (use "git add <file>..." to update staging area)
  (use "git checkout -- <file>..." to discard changes in working tree)

        modified:   src/checkout/ViewCheckout.tsx
        modified:   src/checkout/PresenterCheckout.ts

Untracked files:
  (use "git add" to include in what will be committed)
        src/checkout/__tests__/ViewCheckout.test.tsx

── WITH RTK (6 tokens) ──────────────────────────────────────────────
M src/checkout/ViewCheckout.tsx
M src/checkout/PresenterCheckout.ts
? src/checkout/__tests__/ViewCheckout.test.tsx
```

**~84% reduction** on a single status call. Across a full session with dozens of shell calls — `git diff`, `tsc`, `jest`, `lint` — savings compound to **60–90% on AI input tokens**.

---

### Caveman — compresses AI output (response verbosity)

The `caveman` rule strips filler, articles, hedging, and pleasantries from every response. The AI says the same thing in fewer tokens.

**Code review finding — before vs after Caveman:**

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

**~72% reduction** per finding. Full review sessions with reasoning, plans, and multi-step output: **40–60% output token savings**.

---

### Combined impact

| Layer | What it compresses | Typical savings |
|-------|--------------------|-----------------|
| RTK | Shell output → AI input | 60–90% on dev operations |
| Caveman | AI reasoning → AI output | 40–60% on prose responses |
| **Combined** | Both directions | **50–80% total session cost** |

A typical feature review session without compression: ~40,000 tokens.
With RTK + Caveman: ~8,000–20,000 tokens. Same findings, fraction of the cost.

---

## Install

```bash
git clone git@github.com:raditia/agentic-skills.git ~/agentic-skills
cd ~/agentic-skills
bash install.sh
```

`install.sh` wires up the post-merge hook and runs the first sync. After that, `git pull` keeps everything up to date automatically.

**Requirements:** bash 3.2+, curl. macOS ships bash 3.2 by default — no upgrade needed.
Optional: `jq` for Copilot VS Code settings integration.

**Per-project Copilot `@` agents** (run inside any project repo):
```bash
bash ~/agentic-skills/scripts/init-copilot-agents.sh
# then commit .github/ to share with your team
```

---

## Where content lands

Three tiers by source directory — no frontmatter flag needed:

```
┌────────────────────────────────────────────────────────────────────────┐
│  rules/  →  ALWAYS-ON (auto-loaded every session, never invoked)       │
├────────────────────────────────────────────────────────────────────────┤
│  Claude Code  │  ~/.claude/CLAUDE.md                  (managed section)│
│  Cursor       │  ~/.cursor/rules/<name>.mdc           (alwaysApply:true)│
│  Copilot      │  codeGeneration.instructions + reviewSelection          │
│  Gemini CLI   │  ~/GEMINI.md                          (managed section)│
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│  skills/ and commands/  →  ON-DEMAND (slash cmd or natural language)   │
├────────────────────────────────────────────────────────────────────────┤
│  Claude Code  │  ~/.claude/commands/<name>.md  →  /<name>              │
│  Cursor       │  ~/.cursor/rules/<name>.mdc    (alwaysApply:false)     │
│  Copilot      │  codeGeneration.instructions   (say skill name / ask)  │
│  Gemini CLI   │  ~/GEMINI.md                   (managed section)       │
└────────────────────────────────────────────────────────────────────────┘
```

> **Copilot Chat — two layers:**
> - **Global (auto):** skills loaded via `codeGeneration.instructions` — natural language trigger in any repo
> - **Per-project (`@` invocation):** run `scripts/init-copilot-agents.sh` inside a project to generate `.github/agents/*.agent.md` and `.github/copilot-instructions.md` — enables `@fe-test`, `@fe-review`, `@debug` etc. in Copilot Chat. Commit `.github/` to share with your team.

State tracking in `~/.agentic-skills-state/` — one file per adapter, one skill name per line.

---

## Model routing

Each skill runs on the everyday model by default. When the AI detects genuine uncertainty it outputs an `ESCALATE:` block and asks you to switch.

```
┌──────────────┬───────────────────────┬──────────────────────┐
│ AI           │ Everyday              │ Escalate to          │
├──────────────┼───────────────────────┼──────────────────────┤
│ Claude Code  │ claude-sonnet-4-6     │ claude-opus-4-7      │
│ Gemini CLI   │ gemini-2.5-flash      │ gemini-2.5-pro       │
│ Cursor       │ claude-sonnet / gpt-4o│ claude-opus / o1     │
│ Copilot      │ claude-sonnet-4-6     │ claude-opus-4-7      │
└──────────────┴───────────────────────┴──────────────────────┘
```

> Copilot uses Claude models — select them in the VS Code model picker.

**Escalation is inline — no model switching required.** When the AI detects genuine uncertainty it consults the higher model directly, informs you with a one-line note, incorporates the result, and continues on the everyday model:

```
Low confidence on [specific problem] — consulting higher model.
...
[consulted claude-opus-4-7 for: architecture tradeoff on X]
```

Escalation is reserved for genuine uncertainty — architecture decisions with non-obvious tradeoffs, security-sensitive changes, or debugging with no hypothesis after 2 attempts. Everyday tasks stay on the fast model.

---

## Skills

### Rules — always active, never invoked

Loaded automatically from `rules/` on every session. Never call these — they're always present.

| Rule | What it enforces |
|------|-----------------|
| [`caveman`](rules/caveman.md) | Output compression: terse responses, no filler, full accuracy — lite/full/ultra modes |
| [`fe-rules`](rules/fe-rules.md) | EVPMR layer constraints, TypeScript strict mode, styling tokens, React correctness, tracking |
| [`karpathy-guidelines`](rules/karpathy-guidelines.md) | Coding discipline: think before coding, simplicity, surgical changes, goal-driven execution, read before write, tests verify intent, checkpoint after steps |
| [`using-agent-skills`](rules/using-agent-skills.md) | Skill routing, model selection, severity labels, core operating behaviors — includes: use model for judgment only, surface token budget pressure, surface conflicts never average them |

### Orchestrators — natural language workflow commands

Say what you want in plain language. **Dynamic parallel is the default** for build, review, and ship — the classifier reads the diff, selects only relevant agents, and runs them concurrently. Static sequential commands remain available via explicit slash command for lightweight runs.

#### Dynamic (default — natural language triggers these)

| Command | Say… | What it runs |
|---------|------|--------------|
| [`/parallel-build`](commands/parallel-build.md) | "build feature X", "create a new screen", "implement X", "scaffold a module" | fe-context → scaffold → implement → [tsc ‖ lint] → classify → [relevant agents in parallel] → fe-test |
| [`/parallel-review`](commands/parallel-review.md) | "help me review", "review the changes", "code review", "LGTM check" | [tsc ‖ lint ‖ test] → classify diff → [relevant agents in parallel] → synthesize |
| [`/parallel-ship`](commands/parallel-ship.md) | "get this ready to merge", "ship this", "prepare for PR", "is this ready?" | [tsc ‖ lint ‖ test+coverage] → classify diff → [relevant agents in parallel] → synthesize |
| [`/fix`](commands/fix.md) | "something is broken", "fix this bug", "this crashes", "why is X not working" | fe-context → debug (reproduce → isolate → fix) → fe-test |
| [`/pr-message`](commands/pr-message.md) | "generate PR message", "write PR description", "draft a PR", "what should my PR say" | diff → message → clipboard |
| [`/fe-test`](skills/fe-test/SKILL.md) | "write tests", "add tests", "test this", "coverage is low", "improve coverage", "missing tests" | write/improve tests, enforce ≥ 93% coverage |

#### Sequential (explicit slash command only — lightweight fallback)

| Command | When to prefer |
|---------|---------------|
| [`/review`](commands/review.md) | Quick sanity check, small diff, no parallel overhead needed |
| [`/ship`](commands/ship.md) | Simple pre-merge gate, already know tests pass |
| [`/build`](commands/build.md) | Scaffold-only run or minimal validation needed |

### Frontend skills — on demand

Invoke when a task is narrower than a full workflow. All prefixed `fe-` — future domain skills follow the same convention (e.g. `be-` for backend).

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`fe-context`](skills/fe-context/SKILL.md) | Generate `docs/context.md` from branch diff | Diff spans > 10 interdependent files |
| [`fe-scaffold`](skills/fe-scaffold/SKILL.md) | Create a new 5-file EVPMR feature module | Novel architecture outside EVPMR |
| [`fe-review`](skills/fe-review/SKILL.md) | EVPMR pattern review only | Architectural conflicts with non-obvious resolution |
| [`fe-patterns`](skills/fe-patterns/SKILL.md) | Composition patterns, hooks discipline, state location | Novel state architecture with non-obvious tradeoffs |
| [`fe-performance`](skills/fe-performance/SKILL.md) | Waterfall elimination, bundle size, re-renders, RN & Next.js perf | Lighthouse regressions with non-obvious root cause |
| [`fe-a11y`](skills/fe-a11y/SKILL.md) | Accessible labels, roles, focus management, dynamic announcements, reduced motion — RN & Next.js | Complex focus flows spanning multiple routes |
| [`fe-test`](skills/fe-test/SKILL.md) | Write/improve tests — enforces ≥ 93% coverage | Can't reach 93%, root cause unclear |

### General skills — on demand

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`code-quality`](skills/code-quality/SKILL.md) | Review (5-axis) or simplify complex code — two modes in one skill | Security-sensitive review, or refactor > 500 lines |
| [`debug`](skills/debug/SKILL.md) | Structured reproduce → isolate → fix | No clear hypothesis after 2 isolation attempts |

---

## Skill workflow

### Always-active layer

Rules load automatically — no commands, no invocation:

```
Every session
      │
      ├─► karpathy-guidelines  — think before coding, simplicity, surgical changes
      ├─► fe-rules             — EVPMR constraints, TypeScript, styling, React correctness
      └─► using-agent-skills   — skill routing, severity labels, core behaviors, skill invocation announcement
```

### Orchestrator workflow

Natural language triggers the dynamic variant by default. Explicit slash commands run the sequential fallback.

```
── DYNAMIC (default — triggered by natural language) ──────────────────────────

"build feature X" / "implement X" / "create a new screen"
  /parallel-build  →  fe-context → fe-scaffold → implement →
                       [tsc ‖ lint] → classify built files →
                       [fe-review ‖ fe-patterns ‖ fe-a11y? ‖ fe-performance? ‖ adversarial?] →
                       fe-test

"review this" / "help me review" / "code review" / "LGTM check"
  /parallel-review  →  read diff → [tsc ‖ lint ‖ test] → classify →
                        [code-quality ‖ fe-review ‖ fe-a11y? ‖ adversarial?] → synthesize

"ship this" / "get this ready to merge" / "prepare for PR" / "is this ready?"
  /parallel-ship  →  read diff → [tsc ‖ lint ‖ test+coverage] → classify →
                      [code-quality ‖ fe-review ‖ fe-performance? ‖ fe-a11y? ‖ adversarial?] → synthesize

── SEQUENTIAL (always linear by nature) ───────────────────────────────────────

"something is broken" / "fix this bug" / "this crashes"
  /fix  →  fe-context → debug (reproduce → isolate → fix) → fe-test

"generate PR message" / "draft a PR"
  /pr-message  →  diff → generate → clipboard

── SEQUENTIAL FALLBACK (explicit slash command only) ──────────────────────────

  /review  →  fe-context → code-quality (5-axis) → fe-review
  /ship    →  fe-test → coverage → tsc → lint → review
  /build   →  fe-context → fe-scaffold → fe-patterns + fe-performance → fe-review → fe-test
```

Dynamic commands use a **classifier** — reads actual diff/files, selects only relevant agents, skips irrelevant ones (test-only diffs skip Phase 2 entirely). See `rules/using-agent-skills.md` for classifier logic.

### Dynamic workflow examples

The classifier reads the diff, identifies which EVPMR layers changed, and picks only the agents that matter. Different diffs produce different agent sets.

---

**Example A — View + Presenter changed** (e.g. new form or screen)

```
git diff shows:
  ViewCheckout.tsx        ← View layer
  PresenterCheckout.ts    ← Presenter layer

         ┌─────────────────────────────────┐
         │  classify: View + Presenter     │
         └────────────┬────────────────────┘
                      │
       ┌──────────────┼──────────────┐
       ▼              ▼              ▼
  code-quality    fe-review      fe-a11y
  (5-axis)        (EVPMR)        (interactive
                                  View present)
       └──────────────┼──────────────┘
                      ▼
                  synthesize
                  → merged findings
```

---

**Example B — Model only changed** (e.g. new type + pure function)

```
git diff shows:
  ModelCheckout.ts        ← Model layer only

         ┌─────────────────────────────────┐
         │  classify: Model only           │
         └────────────┬────────────────────┘
                      │
                      ▼
                 code-quality
                 (correctness +
                  type safety focus)
                      │
                      ▼
                  synthesize
                  → targeted findings, no EVPMR/a11y noise
```

---

**Example C — Test files only**

```
git diff shows:
  __tests__/ViewCheckout.test.tsx
  __tests__/PresenterCheckout.test.tsx

         ┌─────────────────────────────────┐
         │  classify: test files only      │
         └────────────┬────────────────────┘
                      │
                      ▼
              Phase 2 SKIPPED
         (no production code changed —
          deep review adds no value)
                      │
                      ▼
         Phase 1 results only: tsc + lint + test
```

---

**Example D — Large cross-layer change** (3+ EVPMR layers, triggers adversarial)

```
git diff shows:
  EntryCheckout.tsx       ← Entry
  ViewCheckout.tsx        ← View
  PresenterCheckout.ts    ← Presenter
  ModelCheckout.ts        ← Model

         ┌──────────────────────────────────────┐
         │  classify: 4 layers — adversarial    │
         │  triggered (3+ EVPMR layers changed) │
         └────────────┬─────────────────────────┘
                      │
       ┌──────────────┼──────────────┬──────────────┐
       ▼              ▼              ▼              ▼
  code-quality    fe-review      fe-a11y       adversarial
  (5-axis)        (EVPMR)        (View          (devil's
                                  present)       advocate)
       └──────────────┼──────────────┴──────────────┘
                      ▼
                  synthesize
                  → findings + adversarial block
                    "strongest case against merging"
```

---

**Agent selection rules at a glance:**

| What changed | Agents spawned |
|-------------|---------------|
| `View*.tsx` | code-quality + fe-review + fe-a11y |
| `Presenter*.ts` | code-quality + fe-review |
| `Model*.ts` | code-quality |
| `Entry*.tsx` or `Resource*.ts` | fe-review |
| View or Presenter + `/parallel-ship` | + fe-performance |
| 3+ EVPMR layers | + adversarial |
| Auth / payment paths | code-quality (security emphasis) |
| Test files only | Phase 2 skipped |

### How `fe-context` feeds all skills

`/fe-context` runs first and writes `docs/context.md` (≤ 600 lines). Every other skill reads from it instead of re-scanning the project.

```
                         ┌──────────────────────┐
                         │     /fe-context      │
                         │  reads branch diff   │
                         │  writes docs/        │
                         │  context.md ≤600 ln  │
                         └──────────┬───────────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         ▼                          ▼                          ▼
  ┌─────────────┐   ┌────────────────────────┐   ┌────────────────┐
  │ /fe-scaffold│   │   /fe-review           │   │  /fe-test      │
  │             │   │   /fe-patterns         │   │                │
  │  5-file     │   │   /fe-performance      │   │  ≥93%          │
  │  EVPMR      │   │   /code-review         │   │  coverage      │
  │             │   │   /code-simplify       │   │                │
  │             │   │   /debug               │   │                │
  └─────────────┘   └────────────────────────┘   └────────────────┘
```

### Context hierarchy

| Level | Source | What |
|-------|--------|------|
| L1 — Rules | Skill files (always-active) | EVPMR, Token system, Karpathy guidelines |
| L2 — Spec | `docs/context.md` | What's being built, constraints, decisions |
| L3 — Source | Diff output | Files touched by this branch |
| L4 — Errors | On demand | Failing tests, lint errors, TypeScript errors |
| L5 — History | Session | Conversation context |

---

## Architecture pattern (EVPMR)

All frontend features follow a strict 5-file module structure:

```
feature-name/
├── EntryFeatureName.tsx      ← ErrorBoundary + context providers
├── ViewFeatureName.tsx        ← Pure render — calls usePresenter*, no state/effects
├── PresenterFeatureName.ts   ← All hooks, state, React Query — returns plain object
├── ModelFeatureName.ts       ← TypeScript types + pure functions only
└── ResourceFeatureName.ts    ← Content resource keys (display strings)
```

**Layer rules (enforced by `fe-rules` at all times):**

```
View       NEVER  useState / useEffect / API calls
Presenter  NEVER  return JSX
Model      NEVER  import React or cause side effects
Entry      ALWAYS wrap in <ErrorBoundary>
Resource   ALWAYS own display strings — never hardcode in View
Styles     ALWAYS StyleSheet.create() + Token.spacing.* / Token.color.*
```

Async data always typed as discriminated unions:
```ts
type AsyncData<T> =
  | { type: 'NOT_ASKED' }
  | { type: 'LOADING' }
  | { type: 'DATA_READY'; payload: T }
  | { type: 'ERROR'; error: string }
```

---

## Managing skills

**Never manually edit or delete installed skill files** in `~/.claude/`, `~/.cursor/`, or VS Code settings. All installs, updates, and removals are managed by `sync.sh` — editing installed files directly will be overwritten on the next sync.

### Adding a rule (always-on)

1. Create `rules/<name>.md` in this repo
2. Commit and push

Rules load automatically on every session — users never invoke them.

**Frontmatter** (no `alwaysApply` — location implies always-on):
```yaml
---
name: rule-name
description: What this rule enforces
---
```

### Adding a skill (on-demand)

1. Create `skills/<name>/SKILL.md` in this repo
2. Commit and push — end users invoke it by name or natural language

Follow the `fe-` prefix convention for domain-specific skills (e.g. `fe-context`, `be-auth`).

**Frontmatter:**
```yaml
---
name: skill-name
description: One-line description shown in skill discovery
alwaysApply: false
---
```

### Adding a command (workflow orchestrator)

1. Create `commands/<name>.md` in this repo
2. Commit and push

Commands chain multiple skills — they orchestrate, not duplicate.

**Frontmatter** (no `alwaysApply`):
```yaml
---
name: command-name
description: What this workflow does and when to use it
---
```

### Updating a skill or command

Edit the file, commit, and push. `sync.sh` diffs source against installed copy — changed files are re-installed automatically.

### Removing a skill or command

Delete the file/folder from the repo, commit, and push. On the next `git pull`, `sync.sh` detects the removal via state files and uninstalls from every AI tool automatically.

```bash
# Remove a skill
git rm -r skills/<name>/

# Remove a command
git rm commands/<name>.md

git commit -m "remove: <name>"
git push
# end users: git pull → sync runs → removed from all AI tools
```

---

## Tooling

| Tool | Purpose | Auto-installed |
|------|---------|----------------|
| [RTK](https://github.com/rtk-ai/rtk) | Compresses shell commands to save AI input tokens | Yes, on first `bash install.sh` |

Output compression is handled by the [`caveman`](rules/caveman.md) rule — no external tool needed. All shell commands in skills are prefixed with `rtk` — RTK rewrites them transparently so the AI sees short tokens while the shell runs the full command.
