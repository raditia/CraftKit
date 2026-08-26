---
name: ponytail-debt
description: Read-only ledger of all ponytail: comment markers in the repo. Shows what was simplified, the ceiling, and the upgrade trigger. Flags deferrals with no upgrade condition.
alwaysApply: false
---

**Commands:** `rtk grep "ponytail:" . --include="*.ts" --include="*.tsx" --include="*.js"`
**Model:** cheapest tier (see the plan-aware Model routing table in `using-agent-skills`). No escalation, since the task is pure extraction.

---

## Trigger

User says: "show ponytail debt", "list deliberate shortcuts", "what did we defer", or invokes `/ponytail-debt`.

---

## Process

1. Grep repo for `ponytail:` markers, excluding `node_modules/`, `.git/`, build dirs.
2. Parse each marker and extract: what was simplified, ceiling, upgrade trigger.
3. Group by file.
4. Flag entries missing an upgrade trigger with `[no-trigger]`.

---

## Output format

```
<file>:<line> · <what was simplified>. ceiling: <limit>. upgrade: <trigger>.
```

Flag missing upgrade trigger:
```
<file>:<line> · <what>. [no-trigger] deferral may become permanent.
```

End with count: `N shortcuts tracked, M with no upgrade trigger.`

---

## Optional

If user asks, write results to `PONYTAIL-DEBT.md` at repo root.

---

## Boundaries

Read-only. No edits. Does not evaluate whether shortcuts were good decisions; it only surfaces them.
