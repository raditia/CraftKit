---
name: ios-performance
description: Performance patterns for UIKit-based iOS screens within MVVM-C. Covers main-thread discipline, cell reuse & prefetch, image downsampling, layout cost, retain-cycle leaks, and network parallelism.
alwaysApply: false
---

**Commands:** `grep -rn "pattern" Modules/<Module>`, `swiftlint lint --path <file>`
**Model:** everyday — escalate to `claude-opus-4-8` for a jank/leak with non-obvious root cause (profile in Instruments first).

---

> **Core behaviors:** Profile before optimizing (Instruments: Time Profiler, Allocations, Core Animation). Never add complexity without a measured win. See `/using-agent-skills` and `/ios-patterns`.

---

**Context:** No `docs/context.md` required. Read the changed ViewModel/View/Fetcher and profile the actual screen before claiming a bottleneck.

---

## 1. Main-thread discipline (CRITICAL)

UIKit is main-thread only; network/parse/DB is not. Keep the main thread for UI.

```swift
// Fetcher does work off-main, hops back to main for the completion the VM repaints from
DispatchQueue.global(qos: .userInitiated).async {
    let parsed = heavyParse(data)
    DispatchQueue.main.async { completion(.success(parsed)) }
}
```
- **Flag** JSON decode, image decode, disk/DB reads, or regex on the main thread.
- VM receives results on main and calls `action?.setX(...)` — the repaint itself must be on main.

---

## 2. Network parallelism

Independent fetches must not be chained. Fan out, join once.

```swift
// WRONG — serial round trips
fetcherA.fetch { a in fetcherB.fetch { b in self.action?.render(a, b) } }

// CORRECT — parallel via DispatchGroup
let group = DispatchGroup()
var a: A?; var b: B?
group.enter(); fetcherA.fetch { a = $0; group.leave() }
group.enter(); fetcherB.fetch { b = $0; group.leave() }
group.notify(queue: .main) { self.action?.render(a, b) }
```
Orchestrate this in the **ViewModel**, not the VC.

---

## 3. List performance (UITableView / UICollectionView / list-diffing libs)

- **Reuse cells** — always `dequeueReusableCell(withIdentifier:)`; never build a cell per row.
- **Fixed height** — provide `rowHeight`/`estimatedRowHeight` or `sizeForItemAt` up front; self-sizing with autolayout on every cell is expensive for long lists.
- **Prefetch** — implement `UITableViewDataSourcePrefetching` / `collectionView(_:prefetchItemsAt:)` to kick off image/data loads before the row appears.
- **Diffable data sources** — prefer `UITableViewDiffableDataSource` (or the list-diffing lib the module already uses) over full `reloadData()` on small changes.
- **No layout work in `cellForRowAt`** — compute derived display values in the VM/model, hand the cell a ready-to-render view-model.

---

## 4. Images

```swift
// Downsample to the display size instead of decoding full-resolution into memory
let options: [CFString: Any] = [
    kCGImageSourceThumbnailMaxPixelSize: maxDimension * scale,
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceShouldCacheImmediately: true,
]
```
- Use the app's image-loading library's downsampling/caching — don't load full-size images into small views.
- Cancel in-flight image loads on cell reuse (`prepareForReuse`) to avoid wrong-image flashes and wasted bandwidth.

---

## 5. Layout cost

- Prefer programmatic constraints or frame layout that's set once; avoid re-adding constraints on every update — mutate `constant` on stored constraints instead.
- **Flag** deep view hierarchies rebuilt on each repaint. Repaint by mutating existing subviews, not by tearing down and re-adding.
- Rasterize static, complex, non-animating layers only when profiling shows a win (`layer.shouldRasterize`).

---

## 6. Memory / leaks (retain cycles cause growth + zombie work)

- `[weak self]` in every escaping closure (Fetcher completions, `DispatchQueue.*.async`, observers) where `self` is captured — otherwise the VM/VC leaks.
- `action` and `delegate` on the ViewModel must be `weak` (also an `/ios-review` check).
- Cancel pollers / `NetworkTask` / timers / observers in `deinit` or on screen disappear — a running poller after the screen is gone wastes CPU and network.
- Verify with Instruments **Allocations** (persistent growth) + **Leaks** on push/pop cycles of the screen.

---

## 7. Startup / lazy work

- Build heavy dependencies lazily (Coordinator constructs a screen's `getProductionDeps()` only when that screen is shown).
- Don't fetch in `init` — fetch in `onViewDidLoad`/`onViewWillAppear` so an unshown screen costs nothing.

---

## Verification

- [ ] No blocking work (decode/parse/DB) on the main thread — profiled in Time Profiler
- [ ] Independent fetches parallelized (`DispatchGroup`), orchestrated in the VM
- [ ] Long lists reuse cells + prefetch + provide sizing; no per-row layout work in `cellForRowAt`
- [ ] Images downsampled to display size; loads cancelled on reuse
- [ ] `[weak self]` in escaping closures; pollers/observers cancelled on teardown — no leak on push/pop (Instruments Leaks)
- [ ] `swiftlint lint --path <changed-file>` clean

List patterns observed not covered above as **Suggested skill updates**.
