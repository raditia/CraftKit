---
name: code-simplify
description: Reduce code complexity while preserving exact behavior. For comprehension speed, not line count.
alwaysApply: false
---

**Commands:** `rtk tsc`, `rtk jest`, `rtk lint`, `rtk grep "pattern" .`
**Model:** everyday — escalate if simplification touches > 500 lines or requires deep type system reasoning

---

> **Core behaviors:** Understand before touching (Chesterton's Fence). Never change behavior. Submit refactoring separate from feature work. See `/using-agent-skills`.

---

## Load project context

1. Find project root — nearest `package.json` going up from CWD
2. If `docs/context.md` missing → auto-run `/fe-context` steps first
3. **Selective include:** read only `Summary`, `Key Changes`, `Architecture Patterns in Use`
4. If context conflicts with observed code:
   ```
   CONFUSION: docs/context.md says X but code shows Y.
   Options: A) ... B) ... → Which?
   ```

---

## Goal

> "Not fewer lines — code easier to read, understand, modify, and debug."

Test: "Would a new team member understand this faster than the original?"

---

## When to use

- Feature works and tests pass, but implementation feels heavier than needed
- Code review flagged readability or complexity issues
- Deeply nested logic, long functions, or unclear names encountered
- After time-pressure code or post-merge duplication

**When NOT to use:**
- Code is already clean — don't simplify for its own sake
- You don't fully understand the code yet — read first
- Performance-critical path where the "simpler" version would be measurably slower
- Module is about to be rewritten entirely — don't simplify throwaway code

---

## Five principles

### 1. Preserve behavior exactly
Every input, output, side effect, error behavior, and edge case stays identical. If unsure a simplification preserves behavior — don't make it.
```
ASK BEFORE EVERY CHANGE:
→ Same output for every input?
→ Same error behavior?
→ Same side effects and ordering?
→ All tests pass without modification?
```

### 2. Follow project conventions
Simplification means consistency with the codebase, not imposing external preferences.
- EVPMR file structure (Entry / View / Presenter / Model / Resource)
- `StyleSheet.create()` at bottom of file — never inline styles
- `Token.spacing.* / Token.color.* / Token.border.*` — never magic numbers
- `type Props = { ... }` above each component
- Discriminated unions for async state (`NOT_ASKED | LOADING | DATA_READY | ERROR`)
- `rtk grep "StyleSheet.create" .` to see existing patterns before changing

### 3. Clarity over cleverness
Explicit code beats compact code when the compact version requires a mental pause to parse.
```typescript
// UNCLEAR: Nested ternary
const label = isNew ? 'New' : isUpdated ? 'Updated' : isArchived ? 'Archived' : 'Active';

// CLEAR: Guard clauses
function getStatusLabel(item: Item): string {
  if (item.isNew) return 'New';
  if (item.isUpdated) return 'Updated';
  if (item.isArchived) return 'Archived';
  return 'Active';
}
```

### 4. Maintain balance
Over-simplification traps:
- Inlining a helper that named a concept → call site harder to read
- Merging unrelated logic into one "simpler" function → complex function
- Removing abstraction that exists for testability or extensibility
- Optimizing for line count instead of comprehension speed

### 5. Scope to what changed
Simplify recently modified code. No drive-by refactors of unrelated code unless explicitly asked. Unscoped changes create noisy diffs and risk regressions.

---

## Process

### Step 1 — Understand before touching (Chesterton's Fence)

Before changing or removing anything, understand why it exists.

```
BEFORE SIMPLIFYING:
- What is this code's responsibility?
- What calls it? What does it call?
- What are the edge cases and error paths?
- Are there tests defining the expected behavior?
- Why might it have been written this way?
  rtk git log -p -- path/to/file  ← check original context
```

If you can't answer these → read more context first. Don't guess.

### Step 2 — Identify opportunities

**Structural complexity:**

| Pattern | Signal | Simplification |
|---------|--------|----------------|
| Deep nesting (3+ levels) | Hard to follow control flow | Extract to guard clauses or helper functions |
| Long functions (50+ lines) | Multiple responsibilities | Split into focused functions with descriptive names |
| Nested ternaries (> 1 level) | Requires mental stack to parse | if/else chains, switch, or lookup objects |
| Boolean param flags | `doThing(true, false, true)` | Options object or separate functions |
| Repeated conditionals | Same `if` check in multiple places | Extract to named predicate function |

**Naming:**

| Pattern | Signal | Fix |
|---------|--------|-----|
| Generic names | `data`, `result`, `item`, `val` | Rename to content: `userProfile`, `validationErrors` |
| Abbreviated names | `usr`, `cfg`, `btn`, `evt` | Full words — except universal: `id`, `url`, `api` |
| Misleading names | `getX()` that also mutates state | Rename to reflect actual behavior |
| "What" comments | `// increment counter` above `count++` | Delete — the code is clear enough |
| "Why" comments | `// Retry: API is flaky under load` | Keep — carries non-obvious intent the code can't express |

**Redundancy:**

| Pattern | Signal | Fix |
|---------|--------|-----|
| Duplicated logic | Same 5+ lines in multiple places | Extract to shared function |
| Dead code | Unreachable branches, unused vars, commented-out blocks | Remove after confirming |
| Unnecessary wrappers | Wrapper that adds no value | Inline — call the underlying function directly |
| Over-engineered patterns | Factory-for-a-factory, strategy with one strategy | Replace with simple direct approach |
| Redundant type assertions | Casting to a type already inferred | Remove |

**EVPMR-specific:**

| Pattern | Signal | Fix |
|---------|--------|-----|
| View JSX return > ~80 lines | Multiple responsibilities in render | Extract `UI[Name][Section].tsx` sub-component in same folder |
| Presenter hook > ~100 lines | Multiple responsibilities | Split to `usePresenter[Name]Data` + `usePresenter[Name]Handlers` |
| Hardcoded strings in View | `<Text>Submit</Text>` | Move to `Resource[Name].ts` |
| Magic numbers in StyleSheet | `marginTop: 8` | Replace with `Token.spacing.xs` |
| Inline styles | `style={{ margin: 8 }}` | Move to `StyleSheet.create()` at bottom of file |
| `useState` in View | State logic in View layer | Move to Presenter hook |

### Step 3 — Apply incrementally

One simplification at a time. Run after each:
```bash
rtk jest path/to/__tests__/
rtk tsc --noEmit
```

If tests fail → revert and reconsider. Never batch multiple simplifications untested.

**Rule of 500:** If refactor touches > 500 lines, use codemods or AST transforms — not manual edits.

**Never mix simplification with feature work.** Separate commits or PRs.

### Step 4 — Verify the result

```
COMPARE BEFORE AND AFTER:
- Genuinely easier to understand?
- No new patterns inconsistent with codebase?
- Diff is clean — no unrelated changes?
- A teammate would approve this as a net improvement?
```

If the "simplified" version is harder to understand or review → revert. Not every attempt succeeds.

---

## TypeScript / React Native examples

```typescript
// SIMPLIFY: Unnecessary async wrapper
// Before
async function getRoute(id: string): Promise<Route> {
  return await routeService.findById(id);
}
// After
function getRoute(id: string): Promise<Route> {
  return routeService.findById(id);
}

// SIMPLIFY: Verbose conditional assignment
// Before
let label: string;
if (isActive) { label = 'Active'; } else { label = 'Inactive'; }
// After
const label = isActive ? 'Active' : 'Inactive';

// SIMPLIFY: Manual array building
// Before
const activeRoutes: Route[] = [];
for (const route of routes) {
  if (route.isActive) activeRoutes.push(route);
}
// After
const activeRoutes = routes.filter((r) => r.isActive);

// SIMPLIFY: Redundant boolean return
// Before
function isValid(input: string): boolean {
  if (input.length > 0 && input.length < 100) return true;
  return false;
}
// After
function isValid(input: string): boolean {
  return input.length > 0 && input.length < 100;
}
```

```tsx
// SIMPLIFY: Long View — extract discriminated union states into sub-components
// Before: 90-line JSX return with switch/if in the middle
// After: each state is its own UI* component

function UIBusSearchLoading() {
  return <ActivityIndicator style={styles.loader} />;
}

function UIBusSearchError({ message }: { message: string }) {
  return <Text style={styles.errorText}>{message}</Text>;
}

// View stays < 80 lines, delegates to UIBusSearchLoading / UIBusSearchError
```

---

## Red flags

- Simplification requires modifying tests to pass → behavior was changed
- "Simplified" code is longer or harder to follow than the original
- Renaming to match personal preferences, not project conventions
- Removing error handling because "it makes the code cleaner"
- Simplifying code you don't fully understand
- Batching many simplifications into one large, hard-to-review commit
- Refactoring code outside the current task scope without being asked

---

## Verification

- [ ] `rtk jest path/to/__tests__/` — all pass without modification
- [ ] `rtk tsc --noEmit` — zero errors
- [ ] `rtk lint path/to/file.tsx` — zero errors
- [ ] Each simplification is a reviewable, incremental change
- [ ] Diff is clean — no unrelated changes mixed in
- [ ] Project conventions maintained (EVPMR structure, Token.*, StyleSheet.create)
- [ ] No error handling removed or weakened
- [ ] No dead code left behind (unused imports, unreachable branches)

List patterns observed not covered by a skill as **Suggested skill updates**.
