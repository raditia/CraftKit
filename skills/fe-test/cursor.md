---
description: Testing conventions for ground-transport frontend modules
alwaysApply: true
---

Respond briefly — minimal tokens, bullets over prose, no filler. Use `rtk` prefix for terminal commands: `rtk jest`, `rtk tsc`, `rtk ls .`, `rtk grep`.
Before acting, check for `docs/context.md` in the project root (nearest `package.json`). If found, read it first — do not re-scan the project. If not found, tell the user to run `/fe-context` first.
Read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When writing tests for this project:

## Test file location
Always in `__tests__/[ComponentName].test.tsx` inside the feature folder.

## Render helper
Use `renderComponent` from `@traveloka/core/test` — never bare `render` from @testing-library/react.

## Mock all external @traveloka hooks
```ts
jest.mock('@traveloka/core', () => ({
  useContentResource: jest.fn(),
  useTracker: jest.fn(() => jest.fn()),
  useRouter: jest.fn(),
}));

beforeEach(() => {
  (useContentResource as jest.Mock).mockReturnValue({ /* content keys */ });
});
```

## What to cover per file type

**View components:** test loading/error/data states, user interactions (fireEvent), tracking calls. Mock the Presenter hook.

**Presenter hooks:** use renderHook, test state transitions and API call arguments.

**Model files:** pure unit tests for reducers and selectors — no rendering.

## Query elements by testID
Use `getByTestId` / `queryByTestId` — add `testID` props to key elements in View components.

## Never let @traveloka hooks run real implementations in tests.

## Workflow — always follow this order

1. **Diff first:** `rtk git diff main...HEAD --name-only` then `rtk git diff main...HEAD` — understand every changed file and line before writing any test.
2. **Map cases:** for each changed file, list every new/modified branch, state, handler, and edge case.
3. **Write tests** covering all of them — all discriminated union states, all conditionals, all interactions and tracking calls.
4. **Run:** `rtk jest path/to/__tests__/` — all must pass.
5. **Coverage:** `rtk jest --coverage path/to/feature/` — Lines, Branches, Functions, Statements all ≥ 93%. Add tests until threshold is met.
