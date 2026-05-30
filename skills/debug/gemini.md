## Debug Skill

**Response style:** Brief. Minimal tokens. Bullets over prose. No filler.
**Commands:** Use `rtk` prefix — `rtk grep`, `rtk git status`, `rtk jest`, `rtk tsc`.
**Context first:** Read relevant files and understand existing code and patterns before acting. Ask if anything is unclear — never assume.

When debugging, follow this structured process:
1. **Reproduce** — identify exact inputs or conditions triggering the bug.
2. **Isolate** — narrow to the smallest failing unit.
3. **Hypothesize** — state the most likely root cause before reading more code.
4. **Verify** — confirm or disprove using code and traces.
5. **Fix** — apply the minimal change only; do not refactor unrelated code.
6. **Confirm** — describe how to verify the fix.
