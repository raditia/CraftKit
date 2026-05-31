RESPONSE STYLE: Brief. Minimal tokens. Bullets over prose. No filler. Direct only.
COMMANDS: Always use rtk prefix — rtk git diff, rtk git log, rtk git status.
CONTEXT FIRST: Read relevant files and understand existing patterns before acting. Ask if anything is unclear — never assume.

CONTEXT HIERARCHY — structure context from most persistent to most transient:
1. Rules: project-wide conventions (Entry/View/Presenter/Model/Resource, Token styling, RTK) — always in skills
2. Spec: what is being built, constraints, decisions — stored in docs/context.md
3. Source files: only files touched by this branch
4. Errors/tests: failing tests, lint errors, TypeScript errors
5. Conversation history: accumulates; compact when switching tasks

SELECTIVE INCLUDE: only load what is relevant to the current diff. Target < 2,000 lines of focused context. Do not dump entire unrelated files.

COLLECT — run these commands:
- Staged: rtk git diff --cached --name-status + rtk git diff --cached
- Committed not pushed: rtk git log @{u}..HEAD --oneline + rtk git diff @{u}..HEAD
- Pushed vs base: rtk git log main...@{u} --oneline + rtk git diff main...@{u}

INLINE PLAN: before generating, emit a brief step-by-step plan and pause if anything seems wrong.

CONFLICT DETECTION — scan the diff before writing. For each violation found (View with useState, Presenter returning JSX, inline styles, eslint-disable without reason), surface it explicitly:
"CONFLICT: file:line — found X, expected Y. Options: A) ... B) ... Awaiting direction."
Never silently resolve conflicts.

WRITE docs/context.md at the project root (nearest package.json):
- L2: Feature summary (2-4 sentences), constraints, key decisions
- L3: Changed files by layer (staged/committed/pushed) with file roles
- L2: Architecture patterns in use (EVPMR files; state; styling; tracking)
- L4: Known issues (lint errors, TypeScript errors, failing tests)
- L2: Conflicts/ambiguities (unresolved)
- L3: Test coverage needed
- Note context budget at top. Flag if > 2,000 lines.

UPDATE RULE: if docs/context.md exists, update changed sections only — preserve manually added notes.

LOOKUP RULE: for all other tasks, read docs/context.md first using selective include — load only sections relevant to the current task. Surface ambiguity explicitly — never guess.

ANTI-PATTERNS TO AVOID:
- Context starvation: acting without loading context.md
- Context flooding: loading entire files not relevant to the task
- Stale context: using context.md from a different task without refreshing
- Silent confusion: guessing when context conflicts with code
