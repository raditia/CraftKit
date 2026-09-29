---
name: cross-review
description: Two-model review of the current diff. Claude and Codex review independently, answer each other's findings once, and the host synthesizes by evidence. Read-only. Use when a change is high-stakes enough that one model's blind spots are the risk; explicit invocation only.
---

**Model:** everyday for the synthesis. The panelists run on each CLI's own default model.

> Triggered by: "/cross-review", "cross-review this", "have Claude and Codex both review it"

---

## Step 0: Run the panel

From the target project, run the script with a long timeout (both reviews take minutes; in Claude Code use `run_in_background` or `timeout: 600000`):

```bash
bash ~/.craftkit/bin/cross-review.sh [base-ref]
```

Before the first send, the script requires `~/.craftkit/cross-review-allowed-auth` with a `project=/absolute/path` line for this repository (one per approved project) and the allowed CLI status methods, one per line: `claude=claude.ai`, `codex=Logged in using ChatGPT`. `CRAFTKIT_CROSS_REVIEW_POLICY=/path/to/policy` selects another file. The CLIs report the login method but do not prove account identity; check the signed-in accounts separately. The script fails closed if the file is absent or the project or either method differs.

It prints the run directory on success. A non-zero exit prints `cross-review could not run: <reason>`: **report that line and stop.** Do not substitute a same-model review and call it a cross-review; offer the fusion panel (`using-agent-skills`) as the separate workflow it is. Untracked files are never sent; the prompt only counts them, so report them as not reviewed. Binary diffs report a change but do not expose reviewable contents; report them as partial coverage.

Running as Codex: the script calls both CLIs over the network, so it needs approval outside the read-only sandbox.

## Step 1: Read the run

Read `meta.md`, `r1-claude.md`, `r1-codex.md`, `r2-claude.md`, `r2-codex.md`. Findings are numbered per reviewer, so refer to them as `claude-F1`, `codex-F2`.

## Step 2: Adjudicate each finding

| Round-2 outcome | Status | Host action |
|---|---|---|
| Both reported it, or the other replied AGREE | **consensus** | Keep; spot-check the cited `file:line` |
| Withdrawn by its author | **dropped** | Drop unless you can verify it yourself |
| DISPUTE | **disputed** | Read both cited lines and decide. The one with checkable evidence wins; neither → `[UNVERIFIED]` at most `[WARNING]` |
| CANNOT-VERIFY | **single-source** | Verify it yourself, or report at the severity the evidence supports |

Agreement raises confidence; it does not prove a finding. Every finding you keep carries a `grounding` label, and no `[UNVERIFIED]` claim reports as `[ERROR]`.

## Step 3: Report

```
CROSS-REVIEW: <repo> @ <short sha> vs <base>   (run: <dir>)

[ERROR] path:line  claim  (consensus | disputed→upheld | single-source, verified)
[WARNING] ...
[SUGGESTION] ...

Dropped: codex-F3 (withdrawn), claude-F2 (disputed, evidence did not hold)
Not reviewed: untracked files, plus each reviewer's "Not reviewed" list
Panel: claude <version>, codex <version>
```

Then offer `/eval` on the result, so whether cross-review beats a single-model review is measured, not assumed.
