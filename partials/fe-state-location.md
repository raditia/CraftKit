---
name: fe-state-location
description: Where frontend state lives in EVPMR, and the props-drilling threshold that sends it to Context. Spliced into fe-patterns (skill) and fe-patterns (agent).
---

## State location → EVPMR mapping

Before writing state, ask where it lives:

```
Used by one Presenter?          → useState inside that Presenter
Passed through 1-2 levels?      → props, because Context costs indirection
Passed through 3+ levels?       → Context, mounted in Entry
Read by sibling Presenters?     → Context, mounted in the nearest common Entry
Shared but never rendered?      → useRef inside Context, so a write re-renders nothing
Cross-feature shared state?     → Redux (genuinely shared, low-frequency reads)
Async server data?              → React Query in Presenter (useQuery / useMutation)
Display strings?                → Resource file, accessed via useContentResource
```

**3 levels or a sibling Presenter is the Context threshold.** Under it, props stay cheaper. Over it, every intermediate component carries a prop it never reads, and each new consumer edits every file in the chain.

Never put state in View. Never fetch data outside a Presenter.

### Shared state via Context (the props-drilling cure)

Past the threshold, state moves to Context across three EVPMR files. Model owns the context, Entry mounts the provider, Presenter consumes it.

**Model: context plus its hooks.** Split state from action, because `dispatch` identity is stable, so a component that only writes re-renders zero times when state changes:
```ts
// ModelFeature.ts
export const FeatureContextState = createContext<ModelFeature>(null!);
export const FeatureContextAction = createContext<Dispatch<SetStateAction<ModelFeature>>>(null!);

if (__DEV__) {
  FeatureContextState.displayName = 'FeatureContextState';
  FeatureContextAction.displayName = 'FeatureContextAction';
}

export const useFeatureState = () => useContext(FeatureContextState);
export const useFeatureAction = () => useContext(FeatureContextAction);
```

**Entry: provider inside the ErrorBoundary.** State initialized from a Model factory, never inside View:
```tsx
function FeaturePage() {
  const [state, dispatch] = useState(ModelFeatureInitial());
  return (
    <FeatureContextState.Provider value={state}>
      <FeatureContextAction.Provider value={dispatch}>
        <ViewFeature />
      </FeatureContextAction.Provider>
    </FeatureContextState.Provider>
  );
}
```

**Presenter: the only consumer.** View calls `usePresenterFeature()` and never `useContext`, which keeps the layer intact and leaves one test surface:
```ts
// PresenterFeature.ts
export function usePresenterFeature() {
  const state = useFeatureState();
  const dispatch = useFeatureAction();
  const handleSelect = useCallback((v: string) => dispatch(setSelected(v)), [dispatch]);
  return { selected: state.selected, handleSelect };
}
```

Four rules that decide whether Context helps or hurts:

| Rule | Why |
|------|-----|
| Split state and action, or `useMemo` the value | One merged `value={{ state, setState }}` is a fresh object every render, so every consumer re-renders even when nothing it reads changed |
| Default `null!`, or `null` with a throwing hook | A plausible fake default lets a consumer outside the provider work silently, then diverge in production |
| Provider in Entry, never in View | A View that owns a provider remounts the state it holds and violates the layer |
| Server data stays in React Query | Its cache is already shared by key, so wrapping it in Context duplicates the cache and loses refetch |
