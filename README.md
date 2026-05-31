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

## Install

```bash
git clone git@github.com:raditia/agentic-skills.git ~/agentic-skills
cd ~/agentic-skills
bash install.sh
```

`install.sh` wires up the post-merge hook and runs the first sync. After that, `git pull` keeps everything up to date automatically.

**Requirements:** bash 4+, curl. On macOS: `brew install bash` if needed.
Optional: `jq` for Copilot VS Code settings integration.

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

> **Copilot Chat:** No custom slash commands — Copilot only supports built-in `/explain`, `/fix`, `/tests` etc. Skills are loaded as context files and triggered by natural language: "write tests for this", "review for EVPMR violations", "scaffold a new feature". The `using-agent-skills` rule (always active) routes requests to the right skill automatically.

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
| [`karpathy-guidelines`](rules/karpathy-guidelines.md) | Coding discipline: think before coding, simplicity first, surgical changes, goal-driven execution |
| [`using-agent-skills`](rules/using-agent-skills.md) | Skill routing, model selection, severity labels, core operating behaviors, failure modes |

### Orchestrators — natural language workflow commands

Say what you want in plain language. These bundle the right skills automatically.

| Command | Say… | What it runs |
|---------|------|--------------|
| [`/build`](commands/build.md) | "build feature X", "create a new screen", "implement X" | fe-context → fe-scaffold → fe-patterns + fe-performance → fe-review → fe-test |
| [`/review`](commands/review.md) | "help me review", "review the changes", "LGTM check" | fe-context → code-quality (5-axis) → fe-review (EVPMR) |
| [`/fix`](commands/fix.md) | "something is broken", "fix this bug", "this crashes" | fe-context → debug → fe-test |
| [`/ship`](commands/ship.md) | "get this ready to merge", "ship this", "prepare for PR" | fe-test → coverage → tsc → lint → review |

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
      └─► using-agent-skills   — skill routing, severity labels, core behaviors
```

### Orchestrator workflow

```
"build feature X"
  /build  →  fe-context → fe-scaffold → (fe-patterns + fe-performance) → fe-review → fe-test

"help me review the changes"
  /review  →  fe-context → code-quality (review mode) → fe-review

"something is broken / fix this"
  /fix  →  fe-context → debug → fe-test

"get this ready to merge"
  /ship  →  fe-test → coverage → tsc → lint → review
```

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
