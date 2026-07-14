---
name: pr-message
description: Generate a pull request message from branch commits and diff — title, summary, goal, changed files, test coverage status, and reviewer notes. Copies result to clipboard.
---

**Commands:** `rtk git log`, `rtk git diff`, `rtk git status`, `rtk git remote`
**Model:** cheapest — `claude-haiku-4-5` (Claude), `gemini-2.5-flash` (Gemini), `gpt-4o-mini` (Copilot/Cursor). Escalate to everyday only if diff spans > 15 files with non-obvious interdependencies.

> Triggered by: "generate PR message", "write PR description", "create pull request message", "draft a PR", "PR message for this branch", "write PR for this branch", "what should my PR say"

---

> **Core behaviors:** Surface assumptions before writing. Never invent goals — derive from commits and diff only. See `/using-agent-skills`.

---

## Step 0 — Inline plan

```
PLAN:
1. Detect base branch and current branch name
2. Collect commits and file diff on this branch
3. Check test coverage status (test files present / changed)
4. Derive title + goal from commit messages + diff shape
5. Write PR message (title + body)
6. Humanize via /humanizer if installed (optional)
7. Copy to clipboard
→ Proceeding unless redirected.
```

---

## Step 1 — Branch context

```bash
rtk git remote show origin | grep "HEAD branch"
rtk git rev-parse --abbrev-ref HEAD
rtk git log <base>...HEAD --oneline
rtk git diff <base>...HEAD --name-status
```

Default base to `main` if remote detection fails.

---

## Step 2 — Diff analysis

```bash
rtk git diff <base>...HEAD --stat
rtk git diff <base>...HEAD
```

From the diff, extract:
- **Goal** — infer from commit messages + what changed (be specific, not generic)
- **Changed files** — group by layer or domain (e.g. View, Presenter, tests, config)
- **Test coverage** — test files in the diff? Web/RN: `*.test.*` / `*.spec.*`. Android: `*Test.kt` under `src/test/`. iOS: `*Test.swift` / `*Spec.swift` (Quick). If yes: note what's covered. If no: flag as untested.

---

## Step 3 — Write PR message

```markdown
# <PR title — concise, imperative, < 70 chars. Conventional-commit prefix if branch commits use one (feat:/fix:/etc.).>

## Summary

<1–3 sentences. What this PR does and why. Derived from commits — not generic.>

## Goal

<One sentence. The specific outcome this achieves for users or the system.>

## Changes

| File | Change |
|------|--------|
| `path/to/file` | Brief description of what changed and why |
| ... | ... |

## Test coverage

- [ ] Unit tests added/updated: <yes — list test files / no — reason>
- [ ] Integration tests: <yes / no / not applicable>
- [ ] Manual verification: <describe what to check if no automated tests>

## Notes for reviewer

<Optional. Flag: non-obvious decisions, known trade-offs, areas that need extra attention, follow-up tickets if any.>
```

Rules:
- Title must be concrete and imperative — match the branch's conventional-commit prefix if its commits use one
- Goal must be concrete — "adds X to enable Y" not "improves code"
- File table: only files that matter to the reviewer — skip auto-generated, lock files, trivial renames
- Test coverage: if no test files changed, always flag it explicitly
- Notes section: omit if nothing warrants reviewer attention

---

## Step 3.5 — Humanize pass (optional)

If the [humanizer skill](https://github.com/blader/humanizer) is installed, run the full generated message through it to strip AI-writing tells before copying.

```bash
test -f ~/.claude/skills/humanizer/SKILL.md && echo "humanizer: present" || echo "humanizer: absent"
```

- **Present** → invoke `/humanizer` on the whole message from Step 3. Instruct it to preserve markdown structure verbatim — the `## Changes` table, the test-coverage checkboxes, and any inline `code` must pass through untouched (patterns #14–16 must not collapse them). Use the humanized output as the final message.
- **Absent** → skip silently and use the Step 3 message as-is. No warning.

> Only Claude Code and OpenCode support `/humanizer`. On the other synced tools (Cursor, Copilot, Gemini, Codex, Crush) the file check fails and this step is a no-op — by design.

---

## Step 4 — Copy to clipboard

```bash
echo "<generated message>" | pbcopy          # macOS
echo "<generated message>" | xclip -selection clipboard  # Linux
```

Detect OS and use the appropriate command. After copying, print the full message to terminal so the user can review it inline.

---

## Done

```
PR MESSAGE GENERATED
Title:    <PR title>
Branch:   <branch> → <base>
Commits:  N
Files:    N changed
Tests:    COVERED / UNCOVERED (flag if no test files in diff)
Humanized: YES / SKIPPED (humanizer not installed)
Copied:   YES / FAILED (fallback: message printed above)
```
