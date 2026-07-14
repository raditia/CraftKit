---
name: ios-patterns
description: MVVM-C architecture reference for a modular iOS monorepo. Per-screen Contract/ViewController/View/ViewModel/Factory contract, Fetcher data layer, Coordinator navigation, Dependency-struct DI. Use when designing or understanding an iOS feature screen.
alwaysApply: false
---

**Commands:** `grep -rn "pattern" Modules/<Module>`, `swiftlint lint --path <file>`
**Model:** everyday — escalate for a screen with novel state/effect orchestration not covered below

> Triggered by: "how does this screen work", "iOS architecture", "explain this module", "where does state live", "how do I structure an iOS feature"

---

> **Core behaviors:** Patterns serve the architecture — MVVM-C always wins. Read a real sibling feature folder before claiming the pattern; the codebase is the source of truth, this file is the map. See `/using-agent-skills`.

---

**Context:** No `docs/context.md` — iOS modules are not EVPMR. Instead, read one real sibling feature in `Modules/<Module>/<Module>/<Feature>/` to confirm exact naming and imports before acting.

---

## The pattern: MVVM-C

**M**VVM + **C**oordinator + **Factory**. Not VIPER, not TCA, not Clean. Typically mixed Objective-C / Swift, **UIKit-dominant** (SwiftUI, if present, is isolated to the newest `…V2`/`…Revamp` flows only). Newer modules are Swift-forward and cleaner; older modules degrade into more ObjC + list-diffing libs + `.xib`. **When in doubt, copy the cleanest recent sibling in the module.**

### Per-screen file contract

Naming is rigid: **`<Module><Feature><Role>`** (referred to below as `<Prefix>` = `<Module><Feature>`). One folder per screen under `Modules/<Module>/<Module>/<Feature>/`.

| File | Role | Hard rule |
|------|------|-----------|
| `<Prefix>Contract.h` (or `.swift`) | Declares the two seam protocols (below) | The View↔VM boundary lives here, nowhere else |
| `<Prefix>ViewController.swift` | Thin UIKit `UIViewController`. Owns the `<Prefix>View`, forwards UIKit events to the VM, implements `<Prefix>ViewModelAction` to push state into the view | **No business logic** — forward and repaint only |
| `<Prefix>View.swift` | `UIView` subclass, programmatic layout (a constraint DSL + the design-system kit). No logic | **No state, no VM reference** |
| `<Prefix>ViewModel.swift` | `final class …: NSObject, <Prefix>ViewModelProtocol`. All state, logic, tracking. `weak var action` (→ VC) + `weak var delegate` (→ Coordinator). Init takes a `Dependency` struct | **Never imports UIKit views; never navigates directly** |
| `<Prefix>Factory.swift` | `makeViewModel(...)` + `makeViewController(...)`. Declares the `<Prefix>ViewModelDependency` struct + `static getProductionDeps()` | DI assembly point |
| `Fetcher/<Prefix>Fetcher` (`.swift` or `.m`) | Data layer behind a `<Prefix>FetcherProtocol` (network via the shared network service, local via the DB layer) | Injected through the Dependency struct |
| `Model/…` | Domain models (ObjC `.h/.m` or Swift) | No view concerns |

### The two seam protocols (the heart of the pattern)

Declared in `<Prefix>Contract.h`. This replaces Combine/Rx — data flow is **imperative push** through these two protocols:

```objc
// VC → VM: events the View Controller forwards
@protocol <Prefix>ViewModelProtocol <NSObject>
@property (nonatomic, weak) id<<Prefix>ViewModelAction> action;
- (void)onViewDidLoad;
- (void)onPrimaryButtonTapped;
@end

// VM → VC: callbacks the ViewModel fires to repaint the view
@protocol <Prefix>ViewModelAction <NSObject>
- (void)setTitleText:(NSString *)text;
- (void)openChildFlow:(<SomeSpec> *)spec;
@end
```

Wiring in the VC:
```swift
init(viewModel: <Prefix>ViewModelProtocol) {
    self.viewModel = viewModel
    super.init(nibName: nil, bundle: nil)
    self.viewModel.action = self        // VM pushes UI updates back through `action`
}
override func viewDidLoad() {
    super.viewDidLoad()
    viewModel.onViewDidLoad()           // VC forwards lifecycle to VM
}
```

VM holds state and repaints by calling `action?`:
```swift
func onViewDidLoad() {
    action?.setTitleText(defaultTitleText)
    dependency.fetcher.fetchConfig()
}
```

---

## State & data flow

| Question | Answer |
|----------|--------|
| Where does state live? | In the **ViewModel** as mutable domain objects (`private(set) var …`) |
| How does the View update? | VM calls `action?.setX(...)`; VC implements `<Prefix>ViewModelAction` and mutates the `<Prefix>View` |
| How does the screen tell the app something happened? | VM fires `delegate?.…(self, didChange: …)` — the Coordinator implements `<Prefix>ViewModelDelegate` |
| Combine / RxSwift / async-await in the view layer? | **No.** Imperative push only. Async results use completion closures or a custom observer/poller (e.g. `…PollingObserver` with `didSuccess/didFail/didUpdateProgress`) |

Newer flows may formalize outputs into explicit `<Prefix>ViewModelOutput` structs and split the single `delegate` into named ones (`actionDelegate`, `coordinatorDelegate`). Same pattern, more structure.

---

## Navigation — Coordinator only

ViewModels **never** call `push/present/pop`. They fire a `delegate` callback; the Coordinator does the navigation.

- Coordinators subclass a shared `BaseCoordinator` (child management via `startChild`).
- A module may ship a thin **`<Module>PublicCoordinator`** (entry from deeplinks / other modules). The primary **`<Module>Coordinator`** consumes the module's public API.
- The Coordinator conforms to each screen's `<Prefix>ViewModelDelegate` and routes via private `navigateToX(...)` helpers.
- Cross-module navigation goes through an app-level navigation API abstraction, never by importing another module's internals.

```swift
override func start() {
    guard let deeplink, let route = <Module>Route(rawValue: deeplink.route) else {
        startFromHome(); return
    }
    if route.isDetail { startFromDetail(deeplinkDetail: deeplink.parseDetailSpec()) }
    else if route.isList { startFromList(...) }
}
```

---

## Dependency injection

Two mechanisms, both manual — no app-wide auto-resolving container required:

1. **Per-screen `Dependency` struct + `getProductionDeps()`** — the dominant pattern. Declared in the Factory, injected via the VM's `init(dependency:)`. Tests pass a hand-built struct of mocks.
   ```swift
   struct <Prefix>ViewModelDependency {
       let fetcher: <Prefix>FetcherProtocol
       let validator: <Module>ValidatorProtocol
       static func getProductionDeps() -> Self {
           Self(fetcher: <Prefix>Fetcher(),
                validator: <Module>Validator())
       }
   }
   ```
2. **A `Factory`-library `@Injected` container** — reserved for cross-cutting app singletons only (metrics, session, etc.):
   ```swift
   @Injected(\MetricsContainer.metricsManager)
   private var metricsManager: MetricsManagerProtocol?
   ```

**Rule:** feature deps → Dependency struct (init injection). App-level services → `@Injected` container.

---

## Networking / data layer — "Fetcher"

Every network/DB access is wrapped in a `<Prefix>Fetcher` behind a `<Prefix>FetcherProtocol`, injected via the Dependency struct.

- **Network:** the shared network service (`POST/GET` with `success:`/`failure:` closures or `Result<T, Error>`) → JSON mapped to domain models. URLs from a `<Module>URLProvider`.
- **Local:** the DB/store layer behind a manager abstraction.
- **Async:** completion closures or a custom cancellable poller. No async/await, no Combine crossing the VM↔View seam.

---

## Module API boundary

`Modules/<Module>/<Module>/ModuleApi/<Module>Module.swift` — a single public façade exposing only `static` factory methods that return **base/protocol types**, hiding concrete VC/VM/Coordinator classes. `@objc` where an ObjC app delegate must call it.

```swift
public final class <Module>Module: NSObject {
    @objc public static func createPublicCoordinator(
        navigationController: UINavigationController,
        input: <Module>PublicCoordinatorInput) -> BaseCoordinator { ... }
}
```

Not every module has a façade — an older module may be reached through its ObjC `Coordinator` directly. If adding a public entry point, add a static method to `<Module>Module.swift`.

---

## Strings / localization

**No per-module resource file for text.** Strings are centralized in the app target: `App/<lang>.lproj/Localizable.strings`. Referenced inline via `NSLocalizedString` with dotted keys:

```swift
NSLocalizedString("<module>.<screen>.<widget>.<descriptor>", comment: "<design-link>")
```

Key scheme: `<module>.<screen>.<widget>.<descriptor>`. Plurals via `String(format: NSLocalizedString("<module>.<screen>.label.item-%ld", ...), count)`. A lint rule commonly forbids assigning `NSLocalizedString(...)` to a `static let/var` (must read live for language switching). `<Module>Resources/` holds **only** image assets + `.xib` — not text.

---

## Legacy vs modern divergences

Within one repo, modules sit on a spectrum. Read before copying:

| Aspect | Modern module (cleaner template) | Legacy module |
|--------|----------------------------------|---------------|
| Language | Swift-forward | More ObjC `.h/.m` |
| Coordinators | Swift | Mostly ObjC |
| Module façade | `<Module>Module.swift` present | May be absent — app uses the `Coordinator` directly |
| Lists | Mixed | List-diffing lib pervasive (`ListDiffable` models) |
| `.xib` | rare | heavy |
| SwiftUI | isolated files | none |

All share: VM-centric logic, `…Action`/`…Delegate` reverse-binding, Fetcher data layer, Quick/Nimble + UI-test targets, central `Localizable.strings`. **When in doubt, copy the newest sibling.**

---

## Build system

**Bazel (primary) + CocoaPods (secondary)**, both glob-driven. A new file dropped in the correct folder is auto-picked-up — no manifest edit. You manually manage only: new cross-module dep (add to `BUILD` `deps=[…]` AND `<Module>.podspec` `s.dependency`), new public entry point (`<Module>Module.swift`), new string (central `Localizable.strings`).

- Build a module: `bazelisk build //Modules/<Module>:<Module>`
- Or generate/open a module-scoped Xcode workspace for day-to-day dev (e.g. `make project_module MODULE=<Module>`).

---

## After using this skill

List any pattern you observed in the code that this map doesn't cover as **Suggested skill updates** — the codebase evolves faster than this doc.
