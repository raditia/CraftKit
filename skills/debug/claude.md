**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk ls .`, `rtk grep "pattern" .`, `rtk git status`, `rtk tsc`, `rtk jest`

---

**Context first:** Read the relevant files, understand the existing code and patterns, confirm what's being asked. Ask if anything is unclear — never assume.

---

## Load project context

Before doing anything else:
1. Find the project root — walk up from CWD to the nearest directory containing `package.json`
2. Check if `docs/context.md` exists there
3. **If found:** read it — use it as your understanding of what's being worked on. Skip re-scanning the project.
4. **If not found:** stop and tell the user: "No context found. Run `/fe-context` first to generate `docs/context.md`."

---

Debug the issue described below or in the current context. Follow this process:

1. **Reproduce**: Identify the exact inputs or conditions that trigger the bug.
2. **Isolate**: Narrow the failure to the smallest possible unit — a function, a query, a request.
3. **Hypothesize**: State the most likely root cause before reading more code.
4. **Verify**: Confirm or disprove the hypothesis by reading relevant code and traces.
5. **Fix**: Apply the minimal change that resolves the root cause. Do not refactor unrelated code.
6. **Confirm**: Explain how to verify the fix works (test command, manual step, or observable behavior).

If the bug has multiple possible causes, address the most likely first and note the others.
