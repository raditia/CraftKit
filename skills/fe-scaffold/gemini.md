## Frontend Scaffold Patterns

**Response style:** Brief. Minimal tokens. Bullets over prose. No filler.
**Commands:** Use `rtk` prefix — `rtk ls .`, `rtk grep`, `rtk git status`, `rtk tsc`, `rtk jest`.
**Context first:** Before acting, check for `docs/context.md` in the project root (nearest `package.json`). If found, read it — do not re-scan the project. If not found, automatically run the fe-context steps to generate `docs/context.md`, then proceed. Then read relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

This project uses a strict Entry/View/Presenter/Model/Resource architecture for every feature module.

**Entry[Name].tsx** — ErrorBoundary + context providers only. No business logic.

**View[Name].tsx** — Pure presentational. Calls `usePresenter[Name]()` at the top and renders JSX from the returned object. Never imports useState, useEffect, or API hooks directly.

**Presenter[Name].ts** — Custom hook containing all state (useState, useReducer), effects, React Query calls, and event handlers. Returns a plain object. Never returns JSX.

**Model[Name].ts** — Pure TypeScript: types, discriminated unions for async data states, reducer functions, selector functions. No React imports.
```ts
type AsyncData<T> = { type: 'NOT_ASKED' } | { type: 'LOADING' } | { type: 'DATA_READY'; payload: T } | { type: 'ERROR'; error: string }
```

**Resource[Name].ts** — i18n content resource keys with empty string defaults.

**Styling rules:**
- Use `StyleSheet.create()` from `react-native` — always at the bottom of the file
- Use `Token.spacing.*`, `Token.color.*`, `Token.border.*` from `@traveloka/web-components`
- No inline styles, no CSS modules, no styled-components

**TypeScript:** strict mode — no `any`, discriminated unions for server state, `type Props = {}` for component props.

**Tracking:** `useTracker()` from `@traveloka/core` for interaction events.
