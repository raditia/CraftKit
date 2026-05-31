---
name: fe-patterns
description: React/React Native composition patterns, hooks discipline, and state location — all mapped to the EVPMR architecture. Use when designing or reviewing component structure.
alwaysApply: false
---

**Commands:** `rtk grep "pattern" .`, `rtk tsc`, `rtk lint`
**Model:** everyday — escalate for novel state architecture with non-obvious tradeoffs

---

> **Core behaviors:** Patterns serve the architecture — EVPMR always wins. When a pattern conflicts with EVPMR, adapt the pattern, not the architecture. See `/using-agent-skills`.

---

## Load project context

1. Find project root — nearest `package.json` going up from CWD
2. If `docs/context.md` missing → auto-run `/fe-context` steps first
3. **Selective include:** read only `Summary`, `Architecture Patterns in Use`, `Key Changes`

---

## State location → EVPMR mapping

Before writing state, ask where it lives:

```
Used by one Presenter?          → useState inside that Presenter
Used by multiple Presenters?    → lift to nearest common ancestor Entry / Context
Cross-feature shared state?     → Redux (genuinely shared, low-frequency reads)
Async server data?              → React Query in Presenter (useQuery / useMutation)
Display strings?                → Resource file, accessed via useContentResource
```

Never put state in View. Never fetch data outside a Presenter.

---

## Hooks discipline

- Top-level only — never conditional or inside loops
- Cleanup every subscription, interval, and listener in return of `useEffect`
- Functional updater when new state depends on old: `setCount(c => c + 1)`
- Default: **do not memoize** — add `useMemo`/`useCallback` only when a profiler proves it matters or a dependency chain requires stability
- Extract to a custom hook only when the same hook sequence appears in 2+ Presenters

### Derive during render — never via `useEffect`

```ts
// WRONG — extra render, can desync
const [full, setFull] = useState('');
useEffect(() => setFull(`${first} ${last}`), [first, last]);

// CORRECT — derive inline
const full = `${first} ${last}`;
```

### Primitive effect dependencies

Objects and arrays get new identity on every render — use primitives as deps:
```ts
// WRONG
useEffect(() => {}, [{ id, name }]);
// CORRECT
useEffect(() => {}, [id, name]);
```

---

## Data fetching decision matrix

| Need | Where | Tool |
|------|-------|------|
| Server data, cached, refetchable | Presenter | React Query `useQuery` |
| Mutation + optimistic update | Presenter | React Query `useMutation` |
| Next.js per-request data (RSC) | Server Component | `await fetch()` / `db.*` |
| One-off fire-and-forget | Presenter handler | `fetch()` in event handler |
| Real-time subscription | Presenter | WebSocket / SSE hook |

Avoid `useEffect` + `fetch` for application data — no cache, no retry, no Suspense integration.

---

## Composition patterns within EVPMR

### Children slot (most common)
```tsx
// Entry provides context, View passes children down
function UICard({ children }: { children: React.ReactNode }) {
  return <View style={styles.card}>{children}</View>;
}
```

### Named slots via props
```tsx
type Props = {
  header: React.ReactNode;
  footer: React.ReactNode;
  children: React.ReactNode;
};
function UILayout({ header, footer, children }: Props) { ... }
```

### Compound components (shared state via Context — lives in Entry)
```tsx
// Entry.tsx — provides context
const TabsContext = createContext<TabsContextValue | undefined>(undefined);

export function EntryBusSearch() {
  return (
    <ErrorBoundary>
      <TabsContext.Provider value={tabsState}>
        <ViewBusSearch />
      </TabsContext.Provider>
    </ErrorBoundary>
  );
}

// View consumes context, never owns it
function UIBusSearchTabs() {
  const { activeTab } = useContext(TabsContext)!;
  return ...;
}
```

### Render props / function-as-child
```tsx
// Useful when a parent must pass dynamic data to rendered output
// Modern alternative: a Presenter hook returning the same shape
<DataLoader id={id}>
  {({ data, isLoading }) => isLoading ? <Spinner /> : <UserCard user={data} />}
</DataLoader>
```

Prefer a Presenter hook (`useDataLoader(id)`) — cleaner, testable.

---

## Custom hook patterns (Presenter layer)

### Toggle
```ts
export function useToggle(initial = false): [boolean, () => void] {
  const [value, setValue] = useState(initial);
  const toggle = useCallback(() => setValue(v => !v), []);
  return [value, toggle];
}
```

### Debounce
```ts
export function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState<T>(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(id);
  }, [value, delay]);
  return debounced;
}
```

### Stable callback ref (for event handlers passed to memoized children)
```ts
function useLatest<T>(value: T) {
  const ref = useRef(value);
  ref.current = value;
  return ref;
}

// In Presenter:
const handlerRef = useLatest(handler);
const stable = useCallback((arg: string) => handlerRef.current(arg), [handlerRef]);
```

---

## Forms within EVPMR

Form state and validation belong in Presenter. View renders dumb inputs.

**Simple forms — Presenter owns state:**
```ts
// PresenterBusSearch.ts
function usePresenterBusSearch() {
  const [origin, setOrigin] = useState('');
  const [errors, setErrors] = useState<{ origin?: string }>({});

  const validate = () => {
    const next: typeof errors = {};
    if (!origin.trim()) next.origin = 'Origin is required';
    setErrors(next);
    return Object.keys(next).length === 0;
  };

  const handleSubmit = useCallback(() => {
    if (!validate()) return;
    // submit
  }, [origin]);

  return { origin, setOrigin, errors, handleSubmit };
}
```

**Complex forms** (multi-step, dynamic fields, cross-field validation) — use React Hook Form or TanStack Form. Rolling your own state for complex forms is a maintenance trap.

**Next.js Server Actions** (web, React 19):
```tsx
'use client';
import { useActionState } from 'react';
const [state, formAction, pending] = useActionState(serverAction, initial);
```
Server action validation with Zod; form state via `useActionState`. Never put business logic in View.

---

## Server / Client split (Next.js)

```tsx
// Server Component — default, no "use client", can async
export default async function PageBusSearch({ params }) {
  const routes = await getRoutes(params.id);
  return <ViewBusSearch routes={routes} />;
}

// Client Component — needed for hooks, interactivity
'use client';
export function ViewBusSearch() {
  const { ... } = usePresenterBusSearch();
  return ...;
}
```

Rules:
- Server → Client: pass serializable props or `children`
- Never `import` a Server Component from a Client Component file — compose via `children`
- Client → Server: via Server Actions (`<form action={...}>` or from event handlers)

---

## Anti-patterns to avoid

| Pattern | Problem | Fix |
|---------|---------|-----|
| `useEffect` to derive state | Extra render, can desync | Derive inline during render |
| Components defined inside components | New type every render, breaks reconciliation | Define at module level |
| `0 && <Component />` | `0` renders as text | `count > 0 ? <Component /> : null` |
| Lifting state to Redux unnecessarily | Shared state should be rare | `useState` in Presenter first |
| Rolling your own fetch in `useEffect` | No cache, retry, Suspense | React Query in Presenter |
| State in View | Violates EVPMR | Move to Presenter |

---

## After review

- [ ] No state in View files
- [ ] No API calls outside Presenter
- [ ] All hooks follow dependency rules
- [ ] `rtk tsc --noEmit` passes
- [ ] `rtk lint` passes

List patterns observed not covered above as **Suggested skill updates**.
