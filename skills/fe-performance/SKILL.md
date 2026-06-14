---
name: fe-performance
description: Performance optimization for React Native and Next.js within the EVPMR pattern. Covers waterfalls, bundle size, re-renders, server-side, and RN-specific patterns.
alwaysApply: false
---

**Commands:** `rtk tsc`, `rtk lint`, `rtk grep "pattern" .`
**Tests:** `rtk test --testPathPattern=<path> --no-coverage` (run from workspace root)
**Model:** everyday — escalate for Lighthouse regressions with non-obvious root cause or complex waterfall chains

---

> **Core behaviors:** Profile before optimizing. Never add complexity without a measured win. See `/using-agent-skills`.

---

**Context:** `docs/context.md` — read: Summary, Key Changes, Architecture Patterns in Use. Standard load procedure in `/using-agent-skills`.

---

## 1. Eliminate waterfalls (CRITICAL)

> Sequential `await` = sequential network latency. Every added `await` is a full round trip.

**Parallelize independent fetches in Presenter:**
```ts
// WRONG — sequential
const user = await getUser(id);
const trips = await getTrips(id);

// CORRECT — parallel
const [user, trips] = await Promise.all([getUser(id), getTrips(id)]);
```

**Defer `await` until the result is actually needed:**
```ts
// WRONG — awaits before checking if needed
const user = await getUser(id);
if (mode === 'guest') return renderGuest();

// CORRECT
if (mode === 'guest') return renderGuest();
const user = await getUser(id);
```

**Check cheap sync conditions before awaiting:**
```ts
// CORRECT — skip remote call if id is missing
if (!id) return null;
const data = await getData(id);
```

**Next.js RSC — split sibling data fetches into child components (React runs them in parallel):**
```tsx
// WRONG — sequential in one component
export default async function Page() {
  const user = await getUser();
  const cart = await getCart();
  return <View user={user} cart={cart} />;
}

// CORRECT — split; React renders children concurrently
export default async function Page() {
  return <View><UserSection /><CartSection /></View>;
}
```

**Use `<Suspense>` close to the data** — don't hoist to route root. Reserve layout space with skeletons to prevent CLS.

---

## 2. Bundle size (CRITICAL)

**Dynamic imports for heavy components:**
```tsx
// Next.js
import dynamic from 'next/dynamic';
const HeavyChart = dynamic(() => import('./HeavyChart'), {
  loading: () => <Skeleton />,
  ssr: false,
});

// React (standard)
const HeavyChart = lazy(() => import('./HeavyChart'));
```

**Direct imports, not barrels** — barrel `index.ts` files force bundlers to load the entire graph:
```ts
// WRONG
import { Button, Card } from '@/components';

// CORRECT
import { Button } from '@/components/Button';
import { Card } from '@/components/Card';
```

**Statically analyzable import paths** — dynamic template literals defeat tree-shaking:
```ts
// WRONG
const mod = await import(`./screens/${name}`);

// CORRECT
const mod = name === 'home' ? await import('./screens/Home') : await import('./screens/Search');
```

**Defer third-party scripts** — use `next/script` with `strategy="afterInteractive"` for analytics, support widgets.

---

## 3. Server-side (Next.js HIGH)

**`React.cache()` for per-request deduplication** — calling the same data function from multiple Server Components costs one DB query, not N:
```ts
import { cache } from 'react';
export const getUser = cache(async (id: string) => db.user.findUnique({ where: { id } }));
```

**Authenticate every Server Action** — `"use server"` functions are public endpoints:
```ts
'use server';
export async function deleteBooking(formData: FormData) {
  const session = await getSession();
  if (!session?.user) throw new Error('Unauthorized');
  // ...
}
```

**Minimize data serialized to Client Components** — strip unused fields at the DB/API layer before passing props.

**`after()` for non-blocking post-response work** (Next.js 15):
```ts
import { after } from 'next/server';
after(() => logAnalytics(data)); // runs after response is sent
```

---

## 4. Re-render optimization (MEDIUM)

> `fe-rules` (always active) covers: derive during render not useEffect, primitive effect deps, functional setState. Not repeated here.

**`React.memo` only when:** component re-renders frequently + props are usually the same + render is measurably expensive. Memo adds an equality check on every render — overhead if props differ on most renders.

**Hoist default non-primitive props** to avoid breaking memo:
```tsx
const EMPTY: Route[] = [];
<RouteList routes={routes ?? EMPTY} />
```

**Subscribe to derived booleans in selectors, not raw values:**
```ts
// WRONG — re-renders on any cart change
const cart = useStore((s) => s.cart);
const hasItems = cart.length > 0;

// CORRECT — re-renders only when emptiness flips
const hasItems = useStore((s) => s.cart.length > 0);
```

**`startTransition` for non-urgent updates** (e.g., filter/sort in search):
```ts
const [pending, startTransition] = useTransition();
startTransition(() => setFilters(newFilters));
```

**`useDeferredValue` for expensive derived renders:**
```ts
const deferredQuery = useDeferredValue(query);
const results = useMemo(() => expensiveSearch(deferredQuery), [deferredQuery]);
```

---

## 5. React Native specific

**`FlatList` over `ScrollView` for long lists** — `ScrollView` renders all children upfront:
```tsx
<FlatList
  data={routes}
  keyExtractor={(item) => item.id}
  renderItem={({ item }) => <RouteCard route={item} />}
  initialNumToRender={10}
  maxToRenderPerBatch={10}
  windowSize={5}
/>
```

**`StyleSheet.create()` is a performance optimization** — styles are registered and referenced by ID, reducing bridge traffic. Never inline style objects (also a `fe-rules` constraint):
```tsx
// WRONG — new object identity on every render
<View style={{ margin: 8 }} />

// CORRECT
<View style={styles.container} />
const styles = StyleSheet.create({ container: { margin: Token.spacing.xs } });
```

**`getItemLayout` on FlatList** when row heights are fixed — skips expensive measurement:
```tsx
getItemLayout={(_data, index) => ({ length: 80, offset: 80 * index, index })}
```

**`removeClippedSubviews`** for very long lists where offscreen views can be unmounted:
```tsx
<FlatList removeClippedSubviews={true} ... />
```

**`useNativeDriver: true`** in Animated — runs animations on the native thread, no JS bridge involvement:
```ts
Animated.timing(opacity, { toValue: 1, useNativeDriver: true }).start();
```

---

## 6. Rendering

**Lazy state initializer for expensive initial values:**
```ts
const [tree] = useState(() => parseTree(largeInput));
```

**`useRef` for high-frequency values that don't drive render** (timestamps, last-key, counters).

---

## 7. Web vitals mapping (Next.js)

| Metric | Most impacted by |
|--------|-----------------|
| **LCP** | Waterfalls, bundle size, resource hints |
| **INP** | Re-renders, JS blocking, startTransition |
| **CLS** | Suspense placement, image dimensions |
| **TBT** | Bundle size, third-party scripts |

---

## Verification

- [ ] `rtk test --testPathPattern=<changed-path> --coverage` — 93% maintained
- [ ] `rtk tsc --noEmit` — zero errors
- [ ] No `Promise.all` opportunities missed in Presenter
- [ ] No inline style objects in React Native components
- [ ] `FlatList` used for lists > ~20 items

List patterns observed not covered above as **Suggested skill updates**.
