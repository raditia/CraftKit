---
name: debug
description: Structured debugging — reproduce, isolate, hypothesize, fix. Use when something is broken.
alwaysApply: false
---

**Commands:** `rtk grep "pattern" .`, `rtk git status`, `rtk tsc`, `rtk jest`
**Model:** everyday — escalate after 2 failed hypotheses with no clear root cause

---

> **Core behaviors:** Surface assumptions before acting. STOP and ask when confused — never guess. Verify the fix works before claiming done. See `/using-agent-skills`.

---

## Load project context

1. Find project root — nearest `package.json` going up from CWD
2. If `docs/context.md` missing → auto-run `/fe-context` steps first
3. **Selective include:** read only `Summary`, `Key Changes`, `Known Issues`, `Conflicts/Ambiguities`
4. If context conflicts with observed code:
   ```
   CONFUSION: docs/context.md says X but code shows Y.
   Options: A) ... B) ... → Which?
   ```

---

## Debug process

1. **Reproduce** — identify exact inputs or conditions that trigger the bug
2. **Isolate** — narrow to the smallest failing unit (function, query, request)
3. **Hypothesize** — state the most likely root cause before reading more code
4. **Verify** — confirm or disprove with code and traces:
   ```bash
   rtk jest path/to/__tests__/file.test.tsx
   rtk tsc --noEmit
   rtk grep "symbol" .
   ```
5. **Fix** — minimal change only. Do not refactor unrelated code.
6. **Confirm** — describe how to verify the fix:
   ```bash
   rtk jest path/to/__tests__/file.test.tsx
   rtk lint path/to/fixed/file.tsx
   ```

If multiple possible causes: address most likely first, note the others.

---

## Scope discipline

- Fix only what is broken
- Do not remove code you don't fully understand
- Do not refactor adjacent code as a side effect
- If the fix requires touching unrelated systems, surface it first:
  ```
  ASSUMPTION: fixing this requires changing X which is outside scope.
  Proceed? Or handle separately?
  ```
