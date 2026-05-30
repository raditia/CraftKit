---
description: Testing conventions for ground-transport frontend modules
alwaysApply: true
---

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
