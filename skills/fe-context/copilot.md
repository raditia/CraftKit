RESPONSE STYLE: Brief. Minimal tokens. Bullets over prose. No filler sentences. Direct only.
COMMANDS: Always use rtk prefix — rtk git diff, rtk git log, rtk git status.
CONTEXT FIRST: Before making any changes, read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When generating or updating feature context:

COLLECT — run these commands:
- Staged (uncommitted): rtk git diff --cached --name-status + rtk git diff --cached
- Committed not pushed: rtk git log @{u}..HEAD --oneline + rtk git diff @{u}..HEAD
- Pushed vs base: rtk git log main...@{u} --oneline + rtk git diff main...@{u}

WRITE — find project root (nearest package.json), create or update docs/context.md with:
- Summary: 2-4 sentences on what is being built
- Changed files grouped by layer (staged / committed-not-pushed / pushed)
- Key changes: bullets on what was added, modified, removed
- Architecture patterns in use: Entry/View/Presenter/Model/Resource files; state, styling, tracking
- Test coverage needed: new or changed files/functions that lack tests

UPDATE RULE: if docs/context.md already exists, update only changed sections — preserve manually added notes.

LOOKUP RULE: for all other tasks, check for docs/context.md in the project root first. If present, read it before proceeding. If absent, tell the user to run /fe-context first.
