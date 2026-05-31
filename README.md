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
                   ├─► sync_adapter()        ← skills/*/SKILL.md
                   │       ├─► checks alwaysApply in frontmatter
                   │       ├─► installs new / updated skills to correct destination
                   │       └─► removes skills deleted from repo
                   │
                   ├─► sync_commands_adapter()  ← commands/*.md
                   │       ├─► always installed as on-demand commands (never rules)
                   │       ├─► installs new / updated commands
                   │       └─► removes commands deleted from repo
                   │
                   └─► finalize_<adapter>()  ← integrity check for managed files
```

Two separate namespaces — both synced automatically on every `git pull`:

| Directory | Purpose | Type |
|-----------|---------|------|
| `skills/` | Specific, single-purpose capabilities | Rules (`alwaysApply: true`) or commands |
| `commands/` | Workflow orchestrators that chain multiple skills | Always on-demand commands |

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

## Where skills land

Skills are split into two tiers by `alwaysApply` in the frontmatter:

```
┌────────────────────────────────────────────────────────────────────────┐
│  alwaysApply: true  →  RULES (auto-loaded every session)               │
├────────────────────────────────────────────────────────────────────────┤
│  Claude Code  │  ~/.claude/CLAUDE.md                  (managed section)│
│  Cursor       │  ~/.cursor/rules/<skill>.mdc           (alwaysApply:true)│
│  Copilot      │  codeGeneration.instructions           (inline + chat) │
│               │  reviewSelection.instructions          (review chat)   │
│  Gemini CLI   │  ~/GEMINI.md                          (managed section)│
└────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────┐
│  alwaysApply: false  →  COMMANDS (invoked by slash cmd or natural lang)│
├────────────────────────────────────────────────────────────────────────┤
│  Claude Code  │  ~/.claude/commands/<skill>.md  →  /<skill>            │
│  Cursor       │  ~/.cursor/rules/<skill>.mdc    (alwaysApply:false)    │
│  Copilot      │  codeGeneration.instructions    (say skill name / ask) │
│  Gemini CLI   │  ~/GEMINI.md                    (managed section)      │
└────────────────────────────────────────────────────────────────────────┘
```

> **Copilot Chat note:** `alwaysApply: true` skills load in both code generation and review chat. `alwaysApply: false` skills (including orchestrators) are in context — trigger them by saying what you want in natural language ("build feature X", "help me review"). `using-agent-skills` routes natural language to the right skill automatically.

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

**Escalation triggers** (defined per skill, surface as):
```
ESCALATE:
Reason: no clear hypothesis after 2 isolation attempts
Recommended: claude-opus-4-7
Claude Code:     /model claude-opus-4-7 → re-invoke the skill
Gemini:          gemini --model gemini-2.5-pro
Cursor / Copilot: switch model in the model picker, then retry
```

Escalation is reserved for genuine uncertainty — architecture decisions with non-obvious tradeoffs, security-sensitive changes, or debugging with no hypothesis after 2 attempts. Everyday tasks stay on the fast model.

---

## Skills

### Always active — no invocation needed

`alwaysApply: true` — loaded automatically on every session. In Claude Code these go into `~/.claude/CLAUDE.md`, not slash commands.

| Skill | What it enforces |
|-------|-----------------|
| [`fe-rules`](skills/fe-rules/SKILL.md) | EVPMR layer constraints, TypeScript strict mode, styling tokens, tracking rules. The AI follows these on every frontend task. |
| [`karpathy-guidelines`](skills/karpathy-guidelines/SKILL.md) | Coding discipline: think before coding, simplicity first, surgical changes, goal-driven execution. |
| [`using-agent-skills`](skills/using-agent-skills/SKILL.md) | Skill routing, model selection, core operating behaviors, failure modes. |

### Orchestrators — natural language workflow commands

Say what you want in plain language. These commands bundle the right skills automatically — no need to invoke each one manually.

| Command | Say… | What it runs |
|---------|------|--------------|
| [`/build`](skills/build/SKILL.md) | "build feature X", "create a new screen for X", "implement X" | fe-context → fe-scaffold → fe-patterns + fe-performance → fe-review → fe-test |
| [`/review`](skills/review/SKILL.md) | "help me review the changes", "review this", "LGTM check" | fe-context → code-review (5-axis) → fe-review (EVPMR) |
| [`/fix`](skills/fix/SKILL.md) | "something is broken", "fix this bug", "this crashes" | fe-context → debug → fe-test |
| [`/ship`](skills/ship/SKILL.md) | "get this ready to merge", "ship this", "prepare for PR" | fe-test → coverage gate → tsc → lint → review |

### Frontend — individual skills

Use when a task is narrower than a full workflow (e.g. just writing tests, or just reviewing patterns).

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`fe-context`](skills/fe-context/SKILL.md) | Load project context only | Diff spans > 10 interdependent files |
| [`fe-scaffold`](skills/fe-scaffold/SKILL.md) | Create a new feature module (5-file EVPMR structure) | Novel architecture outside EVPMR |
| [`fe-review`](skills/fe-review/SKILL.md) | EVPMR pattern review only | Architectural conflicts with non-obvious resolution |
| [`fe-patterns`](skills/fe-patterns/SKILL.md) | Composition patterns, hooks discipline, state location | Novel state architecture with non-obvious tradeoffs |
| [`fe-performance`](skills/fe-performance/SKILL.md) | Waterfall elimination, bundle size, re-renders, RN & Next.js perf | Lighthouse regressions with non-obvious root cause |
| [`fe-test`](skills/fe-test/SKILL.md) | Write/improve tests — enforces ≥ 93% coverage | Can't reach 93%, root cause unclear |

### General — individual skills

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`code-review`](skills/code-review/SKILL.md) | 5-axis quality review (correctness, readability, architecture, security, performance) | Security-sensitive changes or major arch tradeoffs |
| [`code-simplify`](skills/code-simplify/SKILL.md) | Code is working but too complex or hard to read | Refactor > 500 lines or deep type system reasoning |
| [`debug`](skills/debug/SKILL.md) | Structured reproduce → isolate → fix | No clear hypothesis after 2 isolation attempts |

---

## Skill workflow

### Always-active layer

These apply to every task automatically — no invocation, no commands to remember:

```
Every session
      │
      ├─► karpathy-guidelines  — think before coding, simplicity, surgical changes
      ├─► fe-rules             — EVPMR constraints, TypeScript, styling, tracking + React correctness
      └─► using-agent-skills   — skill routing, natural language → orchestrator mapping
```

### Orchestrator workflow

```
"build feature X"
  /build  →  fe-context → fe-scaffold → (fe-patterns + fe-performance during coding) → fe-review → fe-test

"help me review the changes"
  /review  →  fe-context → code-review → fe-review

"something is broken / fix this"
  /fix  →  fe-context → debug → fe-test

"get this ready to merge"
  /ship  →  fe-test → coverage gate → tsc → lint → review
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

### Adding a skill

1. Create `skills/<name>/SKILL.md` in this repo
2. Commit and push — end users get it on the next `git pull`

**Frontmatter:**
```yaml
---
name: skill-name
description: One-line description shown in skill discovery
alwaysApply: false   # true → always-active rule (CLAUDE.md / Cursor always-rule)
                     # false → on-demand command (slash command / natural language)
---
```

### Adding a command (workflow orchestrator)

Commands live in `commands/` — they chain multiple skills and are always installed as on-demand commands (never rules).

1. Create `commands/<name>.md` in this repo
2. Commit and push

**Frontmatter** (no `alwaysApply` — commands are always on-demand):
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
| [RTK](https://github.com/rtk-ai/rtk) | Compresses shell commands to save AI input tokens | Yes, on every `git pull` |
| [Caveman](https://github.com/JuliusBrussee/caveman) | Compresses AI response output tokens | Yes, on every `git pull` |

All shell commands in skills are prefixed with `rtk` — RTK rewrites them transparently so the AI sees short tokens while the shell runs the full command.
