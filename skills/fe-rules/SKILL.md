---
name: fe-rules
description: Always-active EVPMR constraints for React/React Native/Next.js. Follow these at all times when writing or modifying frontend code.
alwaysApply: true
---

Hard constraints for the Entry/View/Presenter/Model/Resource architecture. These are laws, not suggestions — enforced on every frontend task without invocation. For the full review workflow, use `/fe-review`.

---

## Layer constraints

**View (`View*.tsx`) — render only**
- NEVER `useState`, `useEffect`, or direct API/React Query calls
- Call `usePresenter*()` at top — destructure everything from it
- Pure JSX return — no logic, no conditionals beyond rendering
- JSX > ~80 lines → extract `UI[Name][Section].tsx` sub-component in same folder

**Presenter (`Presenter*.ts`) — logic only**
- NEVER return JSX — returns a plain object
- All hooks, state, React Query, `useCallback`, `useMemo` live here
- Hook > ~100 lines → split into `usePresenter[Name]Data` + `usePresenter[Name]Handlers`

**Model (`Model*.ts`) — types and pure functions only**
- No React imports, no side effects
- Async data as discriminated unions:
  ```ts
  type AsyncData<T> =
    | { type: 'NOT_ASKED' }
    | { type: 'LOADING' }
    | { type: 'DATA_READY'; payload: T }
    | { type: 'ERROR'; error: string }
  ```

**Resource (`Resource*.ts`) — strings only**
- All display strings here — never hardcode text in View

**Entry (`Entry*.tsx`) — boundary only**
- Always wraps in `<ErrorBoundary>` from `react-error-boundary`

---

## TypeScript

- `strict: true` — no `any`, no implicit returns
- `type Props = { ... }` above each component
- Exported functions must have explicit return types

---

## Styling

- NEVER inline styles: `style={{ margin: 8 }}` → forbidden
- ALWAYS `StyleSheet.create({})` at the bottom of the file
- ALWAYS design tokens — no magic numbers:
  - Spacing: `Token.spacing.xs / s / m / l / xl`
  - Color: `Token.color.uiBluePrimary / uiLightPrimary / ...`
  - Border: `Token.border.radius.normal`

---

## Tracking

- All user interactions tracked via `useTracker()` from `@traveloka/core`
- Tracking calls belong in Presenter handlers, not in View
