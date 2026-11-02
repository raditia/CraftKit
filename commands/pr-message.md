---
name: pr-message
description: Prepare a PR description with reviewer evidence and commit-bound preflight; include test results, independent review and explicit limitations. Copies result to clipboard.
craftkitInject: change-scope, shape-before-prose
---

**Commands:** `rtk git log`, `rtk git diff`, `rtk git status`, `rtk git remote`
**Model:** cheapest (Claude Code: the injected cheapest tier · Gemini `flash-lite` · Cursor `auto` · Codex default at effort `low`). Escalate to everyday only if diff spans > 15 files with non-obvious interdependencies.

> Triggered by: "generate PR message", "write PR description", "create pull request message", "draft a PR", "PR message for this branch", "write PR for this branch", "what should my PR say"

---

> **Core behaviors:** Surface assumptions before writing. Never invent goals; derive from commits and diff only. See `/using-agent-skills`.

---

## Step 0: Inline plan

```
PLAN:
1. Detect base branch and current branch name
2. Collect commits and file diff on this branch
3. Check test coverage status (test files present / changed)
4. Derive title + goal from commit messages + diff shape
5. Write PR message (title + body)
6. Clarity pass via /clarity (rewrite mode)
7. Copy to clipboard
→ Proceeding unless redirected.
```

---

## Step 1: Branch context

```bash
rtk git symbolic-ref --quiet --short refs/remotes/origin/HEAD
rtk git rev-parse --abbrev-ref HEAD
rtk git log <base>...HEAD --oneline
rtk git diff <base>...HEAD --name-status
```

Resolve the base per `Change scope`; include working-tree changes and relevant untracked files. If no base resolves, report the limitation and describe the visible work without inventing a committed comparison.

---

## Step 2: Diff analysis

```bash
rtk git diff <base>...HEAD --stat
rtk git diff <base>...HEAD
```

From the diff, extract:
- **Goal:** infer from commit messages + what changed (be specific, not generic)
- **Changed files:** group by layer or domain (e.g. View, Presenter, tests, config)
- **Test coverage:** test files in the diff? Web/RN: `*.test.*` / `*.spec.*`. Android: `*Test.kt` under `src/test/`. iOS: `*Test.swift` / `*Spec.swift` (Quick). If yes: note what's covered. If no: flag as untested.

---

## Step 3: Write PR message

```markdown
# <PR title: concise, imperative, < 70 chars. Conventional-commit prefix if branch commits use one (feat:/fix:/etc.).>

## Summary

<1–3 sentences. What this PR does and why. Derived from commits, not generic.>

## Goal

<One sentence. The specific outcome this achieves for users or the system.>

## Changes

| File | Change |
|------|--------|
| `path/to/file` | Brief description of what changed and why |
| ... | ... |

## Test coverage

- [ ] Unit tests added/updated: <yes, list test files / no, reason>
- [ ] Integration tests: <yes / no / not applicable>
- [ ] Manual verification: <describe what to check if no automated tests>

## Notes for reviewer

<Optional. Flag: non-obvious decisions, known trade-offs, areas that need extra attention, follow-up tickets if any.>

## Evidence

<Reviewer-accessible recordings/screenshots for visual or interaction changes; logs, request/response
samples or test output for nonvisual work. Label scenario, expected/actual result, platform/environment,
capture time/timezone and tested commit. Distinguish original bug evidence from fixed behavior.>

<Explicit limitations and unverified scenarios. Missing essential evidence means INCOMPLETE.>
```

Rules:
- Title must be concrete and imperative, matching the branch's conventional-commit prefix if its commits use one
- Goal must be concrete: "adds X to enable Y" not "improves code"
- File table: only files that matter to the reviewer, so skip auto-generated, lock files, trivial renames
- Test coverage: if no test files changed, always flag it explicitly
- Notes section: omit if nothing warrants reviewer attention
- Evidence: use short before/after videos when available, or sufficient screenshots. Open/play the
  uploaded reviewer-facing destination before claiming it verified; local playback alone does not
  establish reviewer access. Use approved durable links, remove secrets/PII, and refresh after
  behavior-changing fixes. Never invent a recording, test result or playback/access verification.

### PR creation preflight

Description-only requests stop at the draft. Before creating a PR, validate the final body and a
JSON record using `node ~/.craftkit/bin/craftkit-pr-preflight.js --record <record.json> --body <body.md>`.
The record contains `version: 1`, `head` (full current SHA), `checks` (name/result/details;
result is `pass` or `blocked`),
`review` (status/agent/summary), `evidence` (kind/url/verified/revision/scenario) and `limitations`
(strings). The helper stamps the repository root and saves the record outside the worktree.
Example shape, with values replaced by actual results:

```json
{
  "version": 1,
  "head": "<full current commit SHA>",
  "checks": [{"name": "project checks", "result": "pass", "details": "<actual output>"}],
  "review": {"status": "pass", "agent": "<independent reviewer ID>", "summary": "<final findings>"},
  "evidence": [{"kind": "video", "url": "https://<reviewer-accessible destination>", "verified": true,
    "revision": "<tested commit SHA>", "scenario": "<action and observed result>"}],
  "limitations": []
}
```

Use an empty evidence array only with explicit limitations in the body; the result is INCOMPLETE,
and any authorized PR is a draft. A successful preflight verifies structure, repository, revision,
clean tracked files and body consistency; checks, independent review and playback remain recorded
claims, not independently observed facts. Do not mark a blocked check as passed to satisfy it.
Put each blocked check's details verbatim in limitations and the body; those records permit
only an INCOMPLETE draft, never READY.
Run after committing, then publish the same body using `gh pr create --body-file <body.md>`.
Use the same preflight with connected PR-creation tools; hook interception covers only the documented
CLI path. After creation, attach the PR where supported and activate `/pr-followup` within scope.

---

## Step 3.5: Clarity pass

Run the full generated message through `/clarity` in rewrite mode to strip AI-writing tells before copying. Instruct it to preserve markdown structure verbatim: the `## Changes` table, the test-coverage checkboxes, and any inline `code` must pass through untouched, and no claim about tests or review evidence may change force. Use its output as the final message.

---

## Step 4: Copy to clipboard

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
Clarity:  APPLIED / FAILED (reason)
Copied:   YES / FAILED (fallback: message printed above)
```
