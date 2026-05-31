---
name: build
description: Full feature build workflow — orchestrates fe-context, fe-scaffold, fe-patterns, fe-performance, fe-review, fe-test in sequence. Use when building a new feature or screen.
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk jest`, `rtk lint`
**Model:** everyday — escalate for architectural decisions with non-obvious tradeoffs

> Triggered by: "build feature X", "create a new screen for X", "scaffold a new module", "implement feature X"

---

## How to run this workflow

Execute each step in order. Each step has a gate — do not proceed until the gate passes.

---

## Step 1 — Context

Run the `/fe-context` workflow:
1. Detect base branch: `rtk git remote show origin | grep 'HEAD branch'`
2. Diff: `rtk git log --oneline <base>...HEAD` and `rtk git diff <base>...HEAD`
3. Read `docs/context.md` if it exists — skip re-generating if diff matches
4. Write `docs/context.md` with sections: Summary, Architecture Patterns in Use, Key Changes, Test Coverage Needed
5. Hard limit: ≤ 600 lines

**Gate:** `docs/context.md` exists and covers the feature scope.

---

## Step 2 — Scaffold

Surface assumptions before creating any files:
```
ASSUMPTIONS I'M MAKING:
1. Feature name: [derived from request]
2. Target platform: [RN / Next.js / both]
3. Data source: [API endpoint / local state / TBD]
→ Correct me now or I'll proceed with these.
```

Create the 5-file EVPMR module:
```
feature-name/
├── EntryFeatureName.tsx      ← ErrorBoundary + context providers
├── ViewFeatureName.tsx       ← Pure render — calls usePresenter*, no state/effects
├── PresenterFeatureName.ts  ← All hooks, state, React Query — returns plain object
├── ModelFeatureName.ts      ← TypeScript types + pure functions only
└── ResourceFeatureName.ts   ← Content resource keys (display strings)
```

Scaffold rules (apply to every file created):
- `strict: true`, no `any`, explicit return types on all exported functions
- `type Props = { ... }` above each component
- Async data typed as discriminated unions: `NOT_ASKED | LOADING | DATA_READY | ERROR`
- All display strings in Resource — never hardcode in View
- View: no `useState`/`useEffect`/API calls; pure JSX only
- Presenter: no JSX; returns plain object
- Entry: always wraps in `<ErrorBoundary>`

**Gate:** All 5 files created, `rtk tsc --noEmit` passes.

---

## Step 3 — Implement (apply patterns + performance continuously)

While writing implementation code, apply these rules at all times:

**State location:**
```
Used by one Presenter?       → useState inside that Presenter
Used by multiple Presenters? → lift to Entry / Context
Async server data?           → React Query useQuery / useMutation in Presenter
Display strings?             → Resource file
```

**Hooks discipline:**
- Derive values during render — never `useEffect` to sync derived state
- Primitive deps in effects — objects/arrays get new identity every render
- No components defined inside components
- Functional setState when new value depends on old: `setCount(c => c + 1)`
- Cleanup every subscription/interval/listener in useEffect return

**Performance (apply as you build, not after):**
- Parallelize independent fetches: `const [a, b] = await Promise.all([getA(), getB()])`
- Direct imports, not barrel imports: `import { X } from '@/components/X'`
- RN: `FlatList` over `ScrollView` for lists, `StyleSheet.create()` always, `useNativeDriver: true` for animations
- Next.js RSC: `React.cache()` for per-request deduplication, authenticate every Server Action
- Conditional render: ternary not `&&` — `count > 0 ? <Badge /> : null`
- Stable `key` props on lists — database ID, never array index

**Gate:** `rtk tsc --noEmit` passes after every logical chunk.

---

## Step 4 — Review

Run the EVPMR checklist before writing tests:

- [ ] No `useState`/`useEffect`/API calls in View
- [ ] No JSX in Presenter
- [ ] All display strings in Resource (no hardcoded text in View)
- [ ] No inline styles — `StyleSheet.create()` + `Token.*` tokens only
- [ ] All tracking calls in Presenter handlers, not in View
- [ ] `rtk tsc --noEmit` clean
- [ ] `rtk lint` clean

Flag any issue as `[ERROR]` (must fix), `[WARNING]` (should fix), or `[SUGGESTION]` (optional).

**Gate:** No `[ERROR]` items remain.

---

## Step 5 — Test

Write tests covering all new code paths:

- All discriminated union states: `NOT_ASKED`, `LOADING`, `DATA_READY`, `ERROR`
- All user interactions and tracking calls
- Every `if/else`, ternary, and optional chaining fallback
- Run: `rtk jest path/to/__tests__/FileName.test.tsx`
- Coverage: `rtk jest --coverage path/to/feature/` — Lines, Branches, Functions, Statements all ≥ 93%

**Gate:** All tests pass. Coverage ≥ 93% on all four metrics.

---

## Done

Report:
- Files created (list all 5)
- `rtk tsc --noEmit` result
- `rtk lint` result
- Tests added, pass/fail count, coverage numbers
