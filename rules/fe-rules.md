---
name: fe-rules
description: Always-active EVPMR constraints for React/React Native/Next.js. Enforced on every frontend task without invocation.
---

Hard constraints for the Entry/View/Presenter/Model/Resource architecture. These are laws, not suggestions. For the full review workflow, use `/fe-review`.

---

## Layer constraints

**View (`View*.tsx`): render only**
- NEVER `useState`, `useEffect`, or direct API/React Query calls
- Call `usePresenter*()` at top, destructure everything from it
- Pure JSX return: no logic, no conditionals beyond rendering
- JSX > ~80 lines → extract `UI[Name][Section].tsx` sub-component in same folder

**Presenter (`Presenter*.ts`): logic only**
- NEVER return JSX; returns a plain object
- All hooks, state, React Query, `useCallback`, `useMemo` live here
- Hook > ~100 lines → split into `usePresenter[Name]Data` + `usePresenter[Name]Handlers`

**Model (`Model*.ts`): types and pure functions only**
- No React imports, no side effects
- Async data as discriminated unions:
  ```ts
  type AsyncData<T> =
    | { type: 'NOT_ASKED' }
    | { type: 'LOADING' }
    | { type: 'DATA_READY'; payload: T }
    | { type: 'ERROR'; error: string }
  ```

**Resource (`Resource*.ts`): strings only**
- All display strings here; never hardcode text in View

**Entry (`Entry*.tsx`): boundary only**
- Always wraps in `<ErrorBoundary>` from `react-error-boundary`

---

## TypeScript

- `strict: true`. No `any`, no implicit returns
- `type Props = { ... }` above each component
- Exported functions must have explicit return types
- **No unused variables** (`no-unused-vars`): remove unused destructured names; if intentionally unused, prefix with `_` (e.g. `_inventoryActive`)

---

## Imports

- **Import the module, never the folder barrel.** A barrel `index.ts` re-exports hooks, providers and contexts next to pure utils, so reaching one helper through it pulls that whole graph (react-query, feature-control and provider code) into the importer:
  ```ts
  // WRONG: drags the barrel's hooks/providers in for one function
  import { getPassengerName } from '@scope/pkg/booking-seat-map';
  // CORRECT
  import { getPassengerName } from '@scope/pkg/booking-seat-map/utils/getPassengerName';
  ```
- **Don't add a new shared helper to the barrel.** Export it from its own file only, because an available barrel path invites the expensive import next time.
- Already importing other symbols from that barrel? There's no graph win, but deep-import anyway for consistency.
- Bonus in tests: a `jest.mock` of the barrel leaves a deep-imported helper real, so it needs no `jest.requireActual` threading.

---

## Styling

- NEVER inline styles: `style={{ margin: 8 }}` → forbidden
- ALWAYS `StyleSheet.create({})` at the bottom of the file
- ALWAYS design tokens, no magic numbers:
  - Spacing: `Token.spacing.xs / s / m / l / xl`
  - Color: `Token.color.uiBluePrimary / uiLightPrimary / ...`
  - Border: `Token.border.radius.normal`

---

## React correctness

- **Derive during render.** Never `useEffect` to sync derived state:
  ```ts
  // WRONG
  const [full, setFull] = useState('');
  useEffect(() => setFull(`${first} ${last}`), [first, last]);
  // CORRECT
  const full = `${first} ${last}`;
  ```
- **No components defined inside components.** New type every render, breaks reconciliation
- **Ternary over `&&`** for conditional render, because `0` renders as text:
  ```tsx
  // WRONG: {count && <Badge />}
  // CORRECT: {count > 0 ? <Badge /> : null}
  ```
- **Primitive deps in effects.** Objects/arrays get new identity every render:
  ```ts
  // WRONG: useEffect(() => {}, [{ id }])
  // CORRECT: useEffect(() => {}, [id])
  ```
- **Stable `key` props.** Use database ID, never array index
- **Functional `setState`** when new state depends on old: `setCount(c => c + 1)`

---

## Tracking

- All user interactions tracked via `useTracker()` from your project's tracking package
- Tracking calls belong in Presenter handlers, not in View
