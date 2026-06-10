---
name: karpathy-guidelines
description: Behavioral rules to reduce common LLM coding mistakes. Always active — applies to every skill and task.
---

> Derived from Andrej Karpathy's observations on LLM coding pitfalls. Adapted for this project's EVPMR architecture and tooling.
>
> **Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

---

## 1. Think before coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing anything non-trivial:
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so and push back.
- If something is unclear, stop. Name what's confusing. Ask.

```
ASSUMPTIONS I'M MAKING:
1. [architecture assumption]
2. [requirement assumption]
→ Correct me now or I'll proceed with these.
```

---

## 2. Simplicity first

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios — trust framework and internal guarantees.
- If you wrote 200 lines and it could be 50, rewrite it.

Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

**EVPMR corollary:** don't pre-split a View into sub-components until it exceeds ~80 lines. Don't pre-split a Presenter until it exceeds ~100 lines. Split when complex, not speculatively.

---

## 3. Surgical changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports, variables, and functions that **your** changes made unused.
- Don't remove pre-existing dead code unless explicitly asked.

Test: every changed line should trace directly to the user's request.

---

## 4. Goal-driven execution

**Define success criteria. Loop until verified.**

Convert vague requests into verifiable goals before starting:

| Vague | Verifiable |
|-------|-----------|
| "Fix the bug" | Write a failing test that reproduces it, then make it pass |
| "Add validation" | Write tests for invalid inputs, then make them pass |
| "Refactor X" | Ensure `rtk test --testPathPattern=<path>` passes before and after |
| "Scaffold the feature" | `rtk tsc --noEmit` and `rtk lint` pass on every generated file |
| Any code change | `npx tsc --noEmit` filtered to changed files — jest skips type checks |

For multi-step tasks, emit a brief plan before starting:
```
PLAN:
1. [step] → verify: [check]
2. [step] → verify: [check]
3. [step] → verify: [check]
→ Proceeding unless redirected.
```

Strong success criteria let you loop independently. "Make it work" requires constant clarification.
