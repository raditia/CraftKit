---
description: Entry/View/Presenter/Model/Resource scaffolding rules for ground-transport monorepo
alwaysApply: true
---

Respond briefly — minimal tokens, bullets over prose, no filler. Use `rtk` prefix for terminal commands: `rtk git status`, `rtk tsc`, `rtk jest`, `rtk ls .`, `rtk grep`.
Before acting, check for `docs/context.md` in the project root (nearest `package.json`). If found, read it first — do not re-scan the project. If not found, automatically run the fe-context steps to generate `docs/context.md`, then proceed.
Read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When creating new frontend feature modules in this codebase, always follow the Entry/View/Presenter/Model/Resource pattern:

## File structure (one folder per feature)

```
[kebab-feature]/
  Entry[Name].tsx      # ErrorBoundary + context providers only
  View[Name].tsx       # Presentational: calls usePresenter hook, returns JSX
  Presenter[Name].ts   # Hook: all state, effects, API calls, handlers
  Model[Name].ts       # Types + pure reducer/selector functions only
  Resource[Name].ts    # contentResource i18n keys (empty string defaults)
  __tests__/
```

## Strict rules

- **View** components must be pure: no useState, no useEffect, no direct API calls. All logic lives in Presenter.
- **Presenter** hooks return a plain object, never JSX.
- **Model** files are pure TypeScript: types and pure functions only, no imports from React.
- **Entry** components wrap in `<ErrorBoundary>` from `react-error-boundary`.

## Async data shape (Model)

Always use discriminated unions for server data:
```ts
type AsyncData<T> =
  | { type: 'NOT_ASKED' }
  | { type: 'LOADING' }
  | { type: 'DATA_READY'; payload: T }
  | { type: 'ERROR'; error: string }
```

## Styling

- All styles via `StyleSheet.create()` from `react-native` at the bottom of each file.
- Use `Token.spacing.*`, `Token.color.*`, `Token.border.*` from `@traveloka/web-components`.
- Never use inline styles. Never use CSS modules, Tailwind, or styled-components.

## TypeScript

- `strict: true` is enforced: no `any`, no implicit returns.
- Use `type Props = { ... }` above the component function.
- Prefer `interface` for API shapes/props, `type` for unions.

## Tracking

Add `useTracker()` from `@traveloka/core` for user interaction events.

## Code quality

- **Single responsibility:** one function/component = one job. If you need "and" to describe it, split it.
- **View length:** JSX return > ~80 lines → extract as `UI[Name][Section].tsx` in the same folder.
- **Presenter length:** hook body > ~100 lines → split into sub-hooks (e.g. `usePresenter[Name]Data`, `usePresenter[Name]Handlers`).
- **No over-engineering:** only split when genuinely complex. No abstractions for single-use code.
- **Readable names:** full words. `isSubmitting` not `isSub`. No nested ternaries — extract to a variable or sub-component.

## ESLint

After every change, run `rtk lint path/to/file.tsx` on each modified file. Fix all errors. Never add `// eslint-disable` without a documented reason in the same comment.
