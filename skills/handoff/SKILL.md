---
name: handoff
description: Compact the current session into a handoff document a fresh agent can pick up — goal, verified state, decisions with their why, ordered next steps, suggested skills. Use near context limit, at end of day, or when moving work to another session. Adapted from mattpocock/skills handoff (MIT).
alwaysApply: false
---

**Model:** cheapest — summarization of material already in context.

---

## Method

1. Write the handoff doc to the OS temp directory (`$TMPDIR/handoff-<slug>.md`), not the workspace — session baggage, not project content. Report the path.
2. Sections:
   - **Goal** — what the overall work is and why
   - **State** — done (with verification evidence) vs in-flight vs not started
   - **Decisions** — each with its why, so the next agent doesn't re-litigate
   - **Next steps** — ordered, acceptance check per step where known
   - **Suggested skills** — which craftkit skills the next agent should invoke to continue (e.g. `/parallel-build` to resume, `/parallel-ship` to verify)
3. **Reference, don't duplicate.** Specs, plans, ADRs, issues, commits, diffs already captured elsewhere → link by path/URL only.
4. **Redact** API keys, tokens, passwords, PII.
5. If the user says what the next session is for, tailor the doc to that focus.
