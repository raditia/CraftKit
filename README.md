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
                   └─► sync_adapter()  ← runs for each AI model
                           │
                           ├─► reads skills/*/SKILL.md
                           ├─► checks alwaysApply in frontmatter
                           ├─► installs new / updated skills to correct destination
                           └─► removes skills deleted from repo
```

Each skill is a single `SKILL.md`. All AI models read from it — no per-model duplication.

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
┌─────────────────────────────────────────────────────────────────┐
│  alwaysApply: true  →  RULES (auto-loaded, no invocation)       │
├─────────────────────────────────────────────────────────────────┤
│  Claude Code  │  ~/.claude/CLAUDE.md          (managed section) │
│  Cursor       │  ~/.cursor/rules/<skill>.mdc  (alwaysApply:true)│
│  Copilot      │  ~/.agentic-skills/copilot/<skill>.md           │
│  Gemini CLI   │  ~/GEMINI.md                  (managed section) │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  alwaysApply: false  →  COMMANDS (invoked explicitly)           │
├─────────────────────────────────────────────────────────────────┤
│  Claude Code  │  ~/.claude/commands/<skill>.md  →  /<skill>     │
│  Cursor       │  ~/.cursor/rules/<skill>.mdc  (alwaysApply:false)│
│  Copilot      │  ~/.agentic-skills/copilot/<skill>.md           │
│  Gemini CLI   │  ~/GEMINI.md                  (managed section) │
└─────────────────────────────────────────────────────────────────┘
```

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

### Frontend — on demand

Designed for React / React Native / Next.js with the EVPMR architecture pattern.

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`fe-context`](skills/fe-context/SKILL.md) | Always first — generates `docs/context.md` from branch diff | Diff spans > 10 interdependent files |
| [`fe-scaffold`](skills/fe-scaffold/SKILL.md) | Creating a new feature module (5-file EVPMR structure) | Novel architecture outside EVPMR |
| [`fe-review`](skills/fe-review/SKILL.md) | Review for EVPMR pattern, TypeScript, styling, ESLint | Architectural conflicts with non-obvious resolution |
| [`fe-test`](skills/fe-test/SKILL.md) | Write/improve tests — enforces ≥ 93% coverage | Can't reach 93%, root cause unclear |

### General — on demand

| Skill | When to use | Escalate if |
|-------|-------------|-------------|
| [`code-review`](skills/code-review/SKILL.md) | Before any merge — 5-axis review (correctness, readability, architecture, security, performance) | Security-sensitive changes or major arch tradeoffs |
| [`code-simplify`](skills/code-simplify/SKILL.md) | Code is working but too complex or hard to read | Refactor > 500 lines or deep type system reasoning |
| [`debug`](skills/debug/SKILL.md) | Something is broken — structured reproduce → isolate → fix | No clear hypothesis after 2 isolation attempts |

---

## Skill workflow

### Always-active layer

These apply to every task automatically — no invocation, no commands to remember:

```
Every session
      │
      ├─► karpathy-guidelines  — think before coding, simplicity, surgical changes
      ├─► fe-rules             — EVPMR constraints, TypeScript, styling, tracking
      └─► using-agent-skills   — skill routing, model selection, core behaviors
```

### On-demand sequences

```
New feature
  /fe-context → /fe-scaffold → /fe-review → /code-review → /fe-test

PR / code review
  /fe-context → /code-review → /fe-review

Bug fix
  /fe-context → /debug → /fe-test

Refactor / simplify
  /fe-context → /code-simplify → /fe-review → /fe-test
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
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
   ┌─────────────┐   ┌──────────────────┐   ┌────────────┐
   │ /fe-scaffold│   │   /fe-review     │   │  /fe-test  │
   │             │   │   /code-review   │   │            │
   │  5-file     │   │   /code-simplify │   │  ≥93%      │
   │  EVPMR      │   │   /debug         │   │  coverage  │
   └─────────────┘   └──────────────────┘   └────────────┘
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

## Adding a new skill

1. Create `skills/<name>/SKILL.md`
2. Run `bash sync.sh` (or `git pull` if the hook is installed)

The skill is automatically installed across all AI models. No other changes needed.

**Frontmatter fields:**
```yaml
---
name: skill-name
description: One-line description shown in skill discovery
alwaysApply: false   # true → writes to CLAUDE.md / Cursor always-rule
                     # false → slash command in Claude Code
---
```

## Removing a skill

Delete `skills/<name>/` and run `bash sync.sh`. The skill is uninstalled from all AI models and removed from `~/.claude/CLAUDE.md` if it was a rule.

---

## Tooling

| Tool | Purpose | Auto-installed |
|------|---------|----------------|
| [RTK](https://github.com/rtk-ai/rtk) | Compresses shell commands to save AI input tokens | Yes, on every `git pull` |
| [Caveman](https://github.com/JuliusBrussee/caveman) | Compresses AI response output tokens | Yes, on every `git pull` |

All shell commands in skills are prefixed with `rtk` — RTK rewrites them transparently so the AI sees short tokens while the shell runs the full command.
