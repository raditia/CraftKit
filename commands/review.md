---
name: review
description: Full code review workflow — orchestrates fe-context, code-review (5-axis), and fe-review (EVPMR). Use when reviewing any frontend change before merge.
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk lint`
**Model:** everyday — escalate for security-sensitive changes or major architecture tradeoffs

> Triggered by: "help me review the changes", "review this", "code review", "review before merge", "LGTM check"

---

## How to run this workflow

Runs in two passes: general quality first, then EVPMR-specific. Report all findings together at the end.

---

## Step 1 — Context

1. Detect base branch: `rtk git remote show origin | grep 'HEAD branch'`
2. Run: `rtk git diff <base>...HEAD --name-only` then `rtk git diff <base>...HEAD`
3. Read `docs/context.md` if present (selective: Summary + Key Changes only)
4. If missing, run the fe-context workflow first

---

## Step 2 — General review (5-axis)

Run the `/code-quality` skill in **review mode** — applies all five axes (correctness, readability, architecture, security, performance) and change sizing.

---

## Step 3 — EVPMR review

Run the `/fe-review` checklist in full. `fe-rules` (always active) defines the layer constraints — flag any violation using the severity labels from `/using-agent-skills`.

---

## Step 4 — Report

Format every finding as:

```
[SEVERITY] File:line — description
Why it matters: ...
Fix: ...
```

Use severity labels from `using-agent-skills`. End with:

```
REVIEW SUMMARY
Errors:      N  (must fix before merge)
Warnings:    N
Suggestions: N
```

If no findings: "No issues found" is a valid outcome.
