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
                   │       ├─► installs RTK   (token compression for AI input)
                   │       └─► installs Caveman (token compression for AI output)
                   │
                   └─► sync_adapter()  ← runs for each AI model
                           │
                           ├─► reads skills/*/SKILL.md
                           ├─► installs new / updated skills
                           └─► removes skills deleted from repo
```

Each skill is a single `SKILL.md` file. All AI models install from it — no per-model duplication.

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

```
SKILL.md
   │
   ├─► Claude Code   ~/.claude/commands/<skill>.md       → invoked as /<skill>
   ├─► Cursor        ~/.cursor/rules/<skill>.mdc          → applied as user rule
   ├─► Copilot       ~/.agentic-skills/copilot/<skill>.md → registered in VS Code settings.json
   └─► Gemini CLI    ~/GEMINI.md (managed section)        → loaded as global context
```

State tracking in `~/.agentic-skills-state/` — one file per adapter, one skill name per line.

---

## Skills

### Frontend development

These skills are designed for React / React Native / Next.js with the Entry/View/Presenter/Model/Resource (EVPMR) architecture pattern.

```
/fe-context   ← Run this first. Generates docs/context.md from branch diff.
     │
     ▼
/fe-scaffold  ← Scaffold a new 5-file EVPMR feature module
/fe-review    ← Check pattern adherence: EVPMR, TypeScript, styling, tests
/fe-test      ← Write tests covering all changed paths. Enforces 93% coverage.
```

| Skill | Description |
|-------|-------------|
| [`fe-context`](skills/fe-context/SKILL.md) | Generates `docs/context.md` from staged/committed/pushed branch changes. Run before any other `fe-*` skill. |
| [`fe-scaffold`](skills/fe-scaffold/SKILL.md) | Scaffold a new feature module: Entry, View, Presenter, Model, Resource. |
| [`fe-review`](skills/fe-review/SKILL.md) | Frontend-specific code review: EVPMR pattern, TypeScript, styling tokens, tracking, ESLint. |
| [`fe-test`](skills/fe-test/SKILL.md) | Write or improve tests covering all changed code paths. Enforces ≥93% coverage on Lines, Branches, Functions, Statements. |

### General — on demand

| Skill | Description |
|-------|-------------|
| [`code-review`](skills/code-review/SKILL.md) | Five-axis review — correctness, readability, architecture, security, performance. Use before any merge. Complements `fe-review`. |
| [`code-simplify`](skills/code-simplify/SKILL.md) | Reduce complexity while preserving exact behavior. For comprehension speed, not line count. |
| [`debug`](skills/debug/SKILL.md) | Structured debugging: reproduce, isolate, hypothesize, fix, confirm. |

### Always active — no invocation needed

These skills have `alwaysApply: true` and load automatically on every session.

| Skill | Description |
|-------|-------------|
| [`karpathy-guidelines`](skills/karpathy-guidelines/SKILL.md) | Behavioral rules applied to every task: think before coding, simplicity first, surgical changes, goal-driven execution. Derived from Andrej Karpathy's LLM coding pitfalls. |
| [`using-agent-skills`](skills/using-agent-skills/SKILL.md) | Skill routing, core operating behaviors, and failure modes. The meta-layer that ties all skills together. |

---

## Skill workflow

Always active (automatic, every session):
```
karpathy-guidelines  ←─ think before coding, simplicity, surgical changes, goal-driven
using-agent-skills   ←─ skill routing, core behaviors, failure modes
```

On-demand workflow — typical sequences:

```
New feature:
  /fe-context → /fe-scaffold → /fe-review → /code-review → /fe-test

PR review:
  /fe-context → /code-review → /fe-review

Bug fix:
  /fe-context → /debug → /fe-test

Refactor / simplify:
  /fe-context → /code-simplify → /fe-review → /fe-test
```

How `fe-context` feeds all other skills:

```
                        ┌─────────────┐
                        │ /fe-context │  ← always first
                        │             │  reads: staged + committed + pushed
                        │             │  writes: docs/context.md (≤ 600 lines)
                        └──────┬──────┘
                               │ all skills below read docs/context.md
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
 ┌────────────┐  ┌─────────────────────┐  ┌──────────────┐
 │/fe-scaffold│  │ /fe-review          │  │ /fe-test     │
 │            │  │ /code-review        │  │              │
 │ new feature│  │ /code-simplify      │  │ tests +      │
 │  5 files   │  │ /debug              │  │ 93% coverage │
 └────────────┘  └─────────────────────┘  └──────────────┘
```

**Context hierarchy** — what each level provides:

| Level | Source | What |
|-------|--------|------|
| L1 — Rules | Skills files | Conventions: EVPMR, Token system, RTK |
| L2 — Spec | `docs/context.md` | What's being built, constraints, decisions |
| L3 — Source | Diff output | Files touched by this branch |
| L4 — Errors | On demand | Failing tests, lint, TypeScript errors |
| L5 — History | Session | Conversation context |

---

## Architecture pattern (EVPMR)

All frontend features follow a strict 5-file module structure:

```
feature-name/
├── EntryFeatureName.tsx      ← ErrorBoundary + context providers
├── ViewFeatureName.tsx       ← Pure render. Calls usePresenter*, no state/effects.
├── PresenterFeatureName.ts   ← All hooks, state, React Query. Returns plain object.
├── ModelFeatureName.ts       ← TypeScript types + pure functions only
└── ResourceFeatureName.ts    ← Content resource keys (display strings)
```

**Key rules:**
- View never has `useState`, `useEffect`, or API calls
- Presenter never returns JSX
- Model never imports React
- All styles via `StyleSheet.create()` at bottom of file
- Design tokens from `@traveloka/web-components`: `Token.spacing.*`, `Token.color.*`, `Token.border.*`
- Async data as discriminated unions: `NOT_ASKED | LOADING | DATA_READY | ERROR`

---

## Adding a new skill

1. Create `skills/<name>/SKILL.md`
2. Run `bash sync.sh` (or `git pull` if the hook is installed)

The skill is automatically installed in all AI models. No other changes needed.

**SKILL.md frontmatter:**
```yaml
---
name: skill-name
description: One-line description shown in skill discovery
alwaysApply: false
---
```

## Removing a skill

Delete `skills/<name>/` and run `bash sync.sh`. The skill is uninstalled from all AI models.

---

## Tooling

| Tool | Purpose | Auto-installed |
|------|---------|----------------|
| [RTK](https://github.com/rtk-ai/rtk) | Compresses shell commands to save input tokens | Yes, on `git pull` |
| [Caveman](https://github.com/JuliusBrussee/caveman) | Compresses AI response output tokens | Yes, on `git pull` |

All shell commands in skills are prefixed with `rtk` — RTK rewrites them transparently.
