---
name: android-performance
description: Performance patterns for Android (Views + RecyclerView and Jetpack Compose) within MVP. Covers main-thread/coroutine discipline, list recycling & DiffUtil, recomposition stability, image loading, overdraw, DFM lazy loading, and leak avoidance.
alwaysApply: false
---

**Commands:** `grep -rn "pattern" <feature>/src`, `./gradlew :<module>:lintGeneralDebug`
**Model:** everyday — escalate to `claude-opus-4-8` for a jank/leak with non-obvious root cause (profile in Android Studio first).

---

> **Core behaviors:** Profile before optimizing (Android Studio Profiler: CPU, Memory, Layout Inspector; recomposition counts). Never add complexity without a measured win. See `/using-agent-skills` and `/android-patterns`.

---

**Context:** No `docs/context.md` required. Read the changed Presenter/repository/View and profile the actual screen before claiming a bottleneck.

---

## 1. Main-thread / coroutine discipline (CRITICAL)

```kotlin
// Repository wraps IO off-main; Presenter launches in its lifecycle scope
suspend fun requestX(p: P): R = withContext(dispatcher.io()) { apiProvider.requestX(p).await() }
```
- **Flag** network, JSON/DB, bitmap decode, or regex on `Dispatchers.Main`.
- Presenter launches in the `CorePresenter` lifecycle scope — **flag** `GlobalScope` (leaks + runs after screen death).
- VM mutations that drive Data Binding must be on main.

---

## 2. Parallelism

```kotlin
// WRONG — serial round trips
val a = repo.getA(); val b = repo.getB()

// CORRECT — concurrent
coroutineScope {
    val a = async { repo.getA() }
    val b = async { repo.getB() }
    render(a.await(), b.await())
}
```
Orchestrate in the **Presenter**, not the View.

---

## 3. RecyclerView

- **DiffUtil / ListAdapter** — never `notifyDataSetChanged()` for list updates; it rebinds everything.
- `setHasFixedSize(true)` when item size doesn't change.
- Compute display values in the Presenter/VM; hand the ViewHolder a ready-to-render item — **no** formatting/business logic in `onBindViewHolder`.
- Share a `RecycledViewPool` across nested/horizontal RecyclerViews.
- Cancel image loads on `onViewRecycled` to avoid wrong-image flashes.

---

## 4. Compose recomposition

- **Stable params** — pass stable/immutable types to Composables; unstable params (mutable classes, `List` from an unstable source) cause needless recomposition. Mark model classes `@Immutable`/`@Stable` where true, or use `ImmutableList`.
- `remember` expensive computations; `derivedStateOf` for values derived from state that changes more often than the derived result.
- **Stable `key`** in `LazyColumn` items — never the index for dynamic lists.
- Hoist state; pass lambdas that are stable (`remember` them or reference method refs) so children don't recompose.
- Defer reads: read state as low in the tree as possible (`Modifier.offset { }` lambda form, not the value form, for scroll-driven values).
- Verify with **recomposition counts** in Layout Inspector — optimize what actually recomposes.

---

## 5. Images

- Use the app's image library (Glide/Coil) with explicit target size / `override(w,h)` — don't decode full-resolution into a small view.
- Enable memory + disk cache; cancel requests on view recycle / `DisposableEffect` cleanup in Compose.

---

## 6. Layout / overdraw (Views)

- Flatten deep hierarchies (`ConstraintLayout` over nested `LinearLayout`); `<merge>`/`ViewStub` for conditional content.
- Remove unnecessary backgrounds that cause overdraw (check with "Debug GPU overdraw").
- Avoid `RelativeLayout` double-measure in long lists.

---

## 7. Startup / lazy work

- Dynamic Feature Modules load on demand — don't force-pull a DFM's code from the base; go through the `-api` NavigatorService.
- Don't fetch in `init`/`onCreate` before the screen is visible — fetch when the View signals it's ready.
- Defer non-critical init (analytics, prefetch) off the critical path.

---

## 8. Memory / leaks

- Cancel coroutines/observers/animators on lifecycle stop — the `CorePresenter` scope should tear down with the screen.
- No `Context`/`View`/`Activity` reference held by a longer-lived object (Presenter/singleton) — leaks the whole screen.
- Verify with the Memory Profiler / LeakCanary on navigate-away.

---

## Verification

- [ ] No blocking work on `Dispatchers.Main` — profiled in CPU profiler
- [ ] Independent fetches concurrent (`async`), orchestrated in the Presenter
- [ ] RecyclerView uses DiffUtil/ListAdapter; no per-row work in `onBindViewHolder`
- [ ] Compose: stable params, keyed lazy items, low recomposition counts (Layout Inspector)
- [ ] Images sized to target + loads cancelled on recycle
- [ ] No leaked scopes/contexts on navigate-away (LeakCanary)
- [ ] `./gradlew :<module>:lintGeneralDebug` clean

List patterns observed not covered above as **Suggested skill updates**.
