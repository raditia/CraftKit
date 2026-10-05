---
name: review
description: Sequential code review workflow, platform-routed at Step 0: context, code-quality (5-axis), and the platform's pattern review. Use when reviewing a change before merge without parallel agents.
craftkitInject: change-scope
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk lint`
**Model:** everyday. Escalate for security-sensitive changes or major architecture tradeoffs

> Triggered by: "help me review the changes", "review this", "code review", "review before merge", "LGTM check"

---

## How to run this workflow

Runs in two passes: general quality first, then EVPMR-specific. Report all findings together at the end.

---

## Step 0: Platform routing

Detect the platform from the changed files, then dispatch:

- **Android** (`*.kt`/`*.java`, Gradle) → run `/code-quality` (5-axis) + `/android-review` (MVP contract). Skip the EVPMR pass.
- **iOS** (`*.swift`/`*.m`, `Modules/`) → run `/code-quality` (5-axis) + `/ios-review` (MVVM-C contract). Skip the EVPMR pass.
- **React Native / web** (`*.tsx`, EVPMR) → continue with the steps below (`/code-quality` + `/fe-review`).

Report format (Step 4) is identical for all platforms.

- **Node / tooling or other repositories:** use the project's architecture and verification commands. Skip EVPMR scaffolding and platform-only checklists; retain general code-quality review and the workflow's completion gates.

---

## Step 1: Context

1. Resolve the base and collect working-tree changes per `Change scope` above
2. Read the complete file set and diffs collected above, including relevant untracked contents
3. Apply standard context loading (`using-agent-skills`): derive Summary + Key Changes once into the turn from the complete change scope; write no context cache

---

## Step 2: General review (5-axis)

Run the `/code-quality` skill in **review mode**, which applies all five axes (correctness, readability, architecture, security, performance) and change sizing.

---

## Step 3: EVPMR review

Run the `/fe-review` checklist in full. `fe-rules` (always active) defines the layer constraints; flag any violation using the severity labels from `/using-agent-skills`.

---

## Step 4: Report

Format every finding as:

```
[SEVERITY] File:line: description
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
