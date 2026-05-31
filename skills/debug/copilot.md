RESPONSE STYLE: Brief. Minimal tokens. Bullets over prose. No filler sentences. Direct only.
COMMANDS: Always use rtk prefix — rtk git status, rtk jest, rtk tsc, rtk grep.
CONTEXT FIRST: Before making any changes, check for docs/context.md in the project root (nearest package.json). If found, read it — do not re-scan the project. If not found, tell the user to run /fe-context first. Then read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When helping debug code, always follow this structured process:
1. Reproduce — identify exact inputs/conditions triggering the bug.
2. Isolate — narrow the failure to the smallest unit.
3. Hypothesize — state the most likely root cause first.
4. Verify — confirm with code and traces.
5. Fix — apply the minimal change only.
6. Confirm — describe how to verify the fix works.
