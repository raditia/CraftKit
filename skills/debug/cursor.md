---
description: Structured debugging — reproduce, isolate, fix — caveman + rtk
alwaysApply: false
---

Respond briefly — minimal tokens, bullets over prose, no filler. Use `rtk` prefix for terminal commands: `rtk git status`, `rtk jest`, `rtk tsc`, `rtk grep`.

When debugging, follow this process:

1. **Reproduce**: Identify the exact inputs or conditions that trigger the bug.
2. **Isolate**: Narrow the failure to the smallest possible unit.
3. **Hypothesize**: State the most likely root cause before reading more code.
4. **Verify**: Confirm or disprove using code and traces.
5. **Fix**: Apply the minimal change. Do not refactor unrelated code.
6. **Confirm**: Describe how to verify the fix.
