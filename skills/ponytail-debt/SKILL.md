---
name: ponytail-debt
description: Read-only ledger of every ponytail: and flag: marker in the repo. Shows what was simplified or gated, the ceiling or OFF behavior, and the upgrade or removal trigger. Flags deferrals with no exit condition.
alwaysApply: false
---

**Commands:** `rtk grep -E "ponytail:|flag:" . --include="*.ts" --include="*.tsx" --include="*.js"`
**Model:** cheapest tier (see the plan-aware Model routing table in `using-agent-skills`). No escalation, since the task is pure extraction.

---

## Trigger

User says: "show ponytail debt", "list deliberate shortcuts", "what did we defer", "list feature flags", "what flags can we remove", or invokes `/ponytail-debt`.

---

## Process

1. Grep repo for `ponytail:` and `flag:` markers, excluding `node_modules/`, `.git/`, build dirs.
2. Parse each marker. `ponytail:` yields what was simplified, ceiling, upgrade trigger. `flag:` (see `flag-safety`) yields the flag key, OFF behavior, removal condition.
3. Group by file, `ponytail:` and `flag:` in separate sections.
4. Flag entries missing an exit condition with `[no-trigger]`. A flag whose removal condition already holds is `[removable]`, since a shipped flag nobody deletes is permanent branching.

---

## Output format

```
<file>:<line> · <what was simplified>. ceiling: <limit>. upgrade: <trigger>.
<file>:<line> · flag <key>. off: <behavior>. remove: <condition>.
```

Flag missing upgrade trigger:
```
<file>:<line> · <what>. [no-trigger] deferral may become permanent.
```

End with count: `N shortcuts tracked, M with no upgrade trigger. K flags live, J removable.`

---

## Optional

If user asks, write results to `PONYTAIL-DEBT.md` at repo root.

---

## Boundaries

Read-only. No edits. Does not evaluate whether shortcuts were good decisions; it only surfaces them.
