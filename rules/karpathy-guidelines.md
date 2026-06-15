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
1. [requirement assumption]
2. [architecture assumption]
→ Correct me now or I'll proceed with these.
```

---

## 2. Simplicity first

**Minimum code that solves the problem. Nothing speculative.**

Before writing any code, stop at the first rung that holds:

1. Does this need to exist at all? (YAGNI)
2. Does the standard library already do this? Use it.
3. Does a native platform feature cover it? Use it.
4. Does an already-installed dependency solve it? Use it.
5. Can this be one line? Make it one line.
6. Only then: write the minimum code that works.

Rules:
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios — trust framework and internal guarantees.
- If you wrote 200 lines and it could be 50, rewrite it.
- Deletion over addition. Boring over clever. Fewest files possible.

Ask: "Would a senior engineer say 'why didn't you just…'?" If yes, simplify.

**Deliberate shortcuts:** when you knowingly pick a simpler approach with a known ceiling (global lock, O(n²) scan, naive heuristic), mark it with a `ponytail:` comment naming the ceiling and upgrade path:
```ts
// ponytail: linear scan over all items. ceiling: >10k rows gets slow. upgrade: add index when perf becomes issue.
```

**EVPMR corollary:** don't pre-split a View into sub-components until it exceeds ~80 lines. Don't pre-split a Presenter until it exceeds ~100 lines. Split when complex, not speculatively.

---

## 3. Surgical changes

**Touch only what you must. Clean up only your own mess.**

Before adding any code, read:
- Exports of the module you're touching
- Immediate callers of the function you're modifying
- Shared utilities that might already solve the problem

"Looks orthogonal" is dangerous. If unsure why code is structured a certain way, ask — don't guess and restructure.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports, variables, and functions that **your** changes made unused.
- Don't remove pre-existing dead code unless explicitly asked.

When your changes add required fields to a type or interface:
- Search test files for mock objects that implement that type and add the missing fields.
- Run `npx tsc --noEmit` on affected test files before reporting done — Jest skips type checks, so TS2739 errors are invisible until CI.

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

"Completed" is wrong if anything was skipped silently. "Tests pass" is wrong if any were skipped. Default: surface uncertainty, never hide it.

---

## 5. Tests verify intent, not just behavior

**Tests must encode WHY behavior matters — not just WHAT it does.**

A test that can't fail when business logic changes is wrong.

Before writing a test, ask: "If someone accidentally deleted the rule this test is protecting, would it fail?" If no → the test is testing implementation, not intent.

```ts
// WRONG — tests what, not why
expect(result.status).toBe('LOADING');

// CORRECT — tests why it matters
// Status must be LOADING during fetch so the UI shows a spinner and blocks interactions
expect(result.status).toBe('LOADING');
expect(result.canSubmit).toBe(false);
```

---

## 6. Checkpoint after every significant step

**Summarize what was done, what's verified, what's left.**

After completing any significant step (scaffold, implementation chunk, test run, type check):

```
CHECKPOINT:
Done:     [what was completed]
Verified: [evidence — test output, tsc clean, lint clean]
Left:     [remaining steps]
```

Don't continue from a state you can't describe. If you lose track, stop and restate before proceeding.
