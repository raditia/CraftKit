---
name: ios-patterns
description: MVVM-C architecture reference for the Traveloka iOS monorepo — Bus and Train modules. Per-screen Contract/ViewController/View/ViewModel/Factory contract, Fetcher data layer, Coordinator navigation, Dependency-struct DI. Use when designing or understanding an iOS bus/train feature.
alwaysApply: false
---

**Commands:** `grep -rn "pattern" Traveloka/Modules/Bus`, `swiftlint lint --path <file>`
**Model:** everyday — escalate for a screen with novel state/effect orchestration not covered below

> Triggered by: "how does bus/train work", "iOS architecture", "explain this screen", "where does state live", "how do I structure an iOS feature"

---

> **Core behaviors:** Patterns serve the architecture — MVVM-C always wins. Read a real sibling feature folder before claiming the pattern; the codebase is the source of truth, this file is the map. See `/using-agent-skills`.

---

**Context:** No `docs/context.md` — iOS modules are not EVPMR. Instead, read one real sibling feature in `Traveloka/Modules/Bus/Bus/<Feature>/` (e.g. `SearchForm/`) to confirm exact naming and imports before acting.

---

## The pattern: MVVM-C

**M**VVM + **C**oordinator + **Factory**. Not VIPER, not TCA, not Clean. Mixed Objective-C / Swift, **UIKit-dominant** (SwiftUI is rare — isolated subviews in the newest `…V2`/`…Revamp` flows only). Bus is the cleaner template; Train is the same pattern degraded into more ObjC + IGListKit + `.xib`.

### Per-screen file contract

Naming is rigid: **`<Module><Feature><Role>`** (e.g. `BusSearchForm…`). One folder per screen under `Traveloka/Modules/<Module>/<Module>/<Feature>/`.

| File | Role | Hard rule |
|------|------|-----------|
| `…Contract.h` (or `.swift`) | Declares the two seam protocols (below) | The View↔VM boundary lives here, nowhere else |
| `…ViewController.swift` | Thin UIKit `UIViewController`. Owns the `…View`, forwards UIKit events to the VM, implements `…ViewModelAction` to push state into the view | **No business logic** — forward and repaint only |
| `…View.swift` | `UIView` subclass, programmatic layout (SnapKit + MUIKit). No logic | **No state, no VM reference** |
| `…ViewModel.swift` | `final class …: NSObject, …ViewModelProtocol`. All state, logic, tracking. `weak var action` (→ VC) + `weak var delegate` (→ Coordinator). Init takes a `Dependency` struct | **Never imports UIKit views; never navigates directly** |
| `…Factory.swift` | `makeViewModel(...)` + `makeViewController(...)`. Declares the `…ViewModelDependency` struct + `static getProductionDeps()` | DI assembly point |
| `Fetcher/…Fetcher` (`.swift` or `.m`) | Data layer behind a `…FetcherProtocol` (network via `TVLNetworkService`, local via Realm) | Injected through the Dependency struct |
| `Model/…` | Domain models (ObjC `.h/.m` or Swift) | No view concerns |

### The two seam protocols (the heart of the pattern)

Declared in `…Contract.h`. This replaces Combine/Rx — data flow is **imperative push** through these two protocols:

```objc
// VC → VM: events the View Controller forwards
@protocol BusSearchFormViewModelProtocol <NSObject>
@property (nonatomic, weak) id<BusSearchFormViewModelAction> action;
- (void)onViewDidLoad;
- (void)onSearchButtonTapped;
@end

// VM → VC: callbacks the ViewModel fires to repaint the view
@protocol BusSearchFormViewModelAction <NSObject>
- (void)setOriginText:(NSString *)text;
- (void)openCalendarPicker:(BusCalendarSpec *)spec;
@end
```

Wiring in the VC:
```swift
init(viewModel: BusSearchFormViewModelProtocol) {
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
    action?.setOriginText(defaultOriginText)
    dependency.searchSpecFetcher.fetchNewConfig()
}
```

---

## State & data flow

| Question | Answer |
|----------|--------|
| Where does state live? | In the **ViewModel** as mutable domain objects (`private(set) var searchSpec`) |
| How does the View update? | VM calls `action?.setX(...)`; VC implements `…Action` and mutates the `…View` |
| How does the screen tell the app something happened? | VM fires `delegate?.…(self, didChange: spec)` — the Coordinator implements `…ViewModelDelegate` |
| Combine / RxSwift / async-await in the view layer? | **No.** Imperative push only. Async results use completion closures or a custom observer/poller (e.g. `…PollingFetcherObserver` with `didSuccess/didFail/didUpdateProgressPercentage`) |

The newer V2 flow formalizes outputs into explicit `…ViewModelOutput` structs and splits the single `delegate` into named ones (`actionDelegate`, `coordinatorDelegate`, `homeDelegate`). Same pattern, more structure.

---

## Navigation — Coordinator only

ViewModels **never** call `push/present/pop`. They fire a `delegate` callback; the Coordinator does the navigation.

- Coordinators subclass a shared `BaseCoordinator` (child management via `startChild`).
- The module ships a thin **`…PublicCoordinator`** (entry from deeplinks / other modules) inside the module. The primary **`…Coordinator`** lives in the **app target** and `import`s the module — it consumes the module's public API.
- The Coordinator conforms to each screen's `…ViewModelDelegate` and routes via private `navigateToX(...)` helpers.
- Cross-module navigation goes through the app delegate: `(UIApplication.shared.delegate as? AppCoordinatorNavigationApi)?.navigateToBookingForm?(...)`.

```swift
override func start() {
    guard let deeplink, let route = BusRoute(rawValue: deeplink.route) else {
        startFromHome(); return
    }
    if route.isDetail { startFromDetail(deeplinkDetail: deeplink.parseDetailSpec()) }
    else if route.isSearchResult { startFromSearchResult(...) }
}
```

---

## Dependency injection

Two mechanisms, both manual — no app-wide Swinject/Resolver container:

1. **Per-screen `Dependency` struct + `getProductionDeps()`** — the dominant pattern. Declared in the Factory, injected via the VM's `init(dependency:)`. Tests pass a hand-built struct of mocks.
   ```swift
   struct BusSearchFormViewModelDependency {
       let searchSpecFetcher: BusSearchSpecFetcherProtocol
       let featureValidator: BusFeatureValidatorProtocol
       static func getProductionDeps() -> Self {
           Self(searchSpecFetcher: BusSearchSpecFetcher(),
                featureValidator: BusFeatureValidator())
       }
   }
   ```
2. **`Factory` library `@Injected`** — reserved for cross-cutting app singletons only (metrics, etc.):
   ```swift
   @Injected(\TVLMetricsCoreExternalContainer.metricsManager)
   private var metricsManager: TVLMetricsManagerProtocol?
   ```

**Rule:** feature deps → Dependency struct (init injection). App-level services → `@Injected` container.

---

## Networking / data layer — "Fetcher"

Every network/DB access is wrapped in a `…Fetcher` behind a `…FetcherProtocol`, injected via the Dependency struct.

- **Network:** `TVLNetworkService.sharedInstance().POST(url, params, success:, failureResponse:)` → JSON mapped via `modelObjectWithDictionary`. URLs from `…URLProvider`.
- **Local:** Realm (`RealmManager.manager().defaultRealm()`).
- **Async:** completion closures or a custom cancellable poller (`TVLNetworkTask` + observer). No async/await, no Combine.

---

## Module API boundary

`Traveloka/Modules/Bus/Bus/ModuleApi/BusModule.swift` — a single public façade exposing only `static` factory methods that return **base/protocol types**, hiding concrete VC/VM/Coordinator classes. `@objc` so the ObjC app delegate can call it.

```swift
public final class BusModule: NSObject {
    @objc public static func createPublicCoordinator(
        navigationController: UINavigationController,
        input: BusPublicCoordinatorInput) -> BaseCoordinator { ... }
}
```

**Train has no `TrainModule`** — the app reaches Train through its ObjC `TrainCoordinator` directly. If adding a public entry point to Bus, add a static method to `BusModule.swift`.

---

## Strings / localization

**No per-module resource file for text.** Strings are centralized in the app target: `Traveloka/Traveloka/<lang>.lproj/Localizable.strings`. Referenced inline via `NSLocalizedString` with dotted keys:

```swift
NSLocalizedString("bus.home.label.origin-text-field-default", comment: "https://zpl.io/...")
```

Key scheme: `<module>.<screen>.<widget>.<descriptor>`. Plurals via `String(format: NSLocalizedString("bus.home.label.seat-%ld-passengers", ...), count)`. The `comment:` field usually holds the Zeplin design link. `BusResources/` holds **only** image assets + `.xib` — not text.

---

## Bus vs Train — divergences

| Aspect | Bus (cleaner template) | Train (more legacy) |
|--------|------------------------|---------------------|
| Language | Swift-forward | More ObjC `.h/.m` |
| Coordinators | Swift | Mostly ObjC; only Seat/Booking are Swift |
| Module façade | `BusModule.swift` | **None** — app uses `TrainCoordinator` directly |
| Lists | Mixed; IGListKit in places | IGListKit pervasive (`ListDiffable` models) |
| `.xib` | rare (3) | heavy (21) |
| SwiftUI | 4 isolated files | 0 |

Both share: VM-centric logic, `…Action`/`…Delegate` reverse-binding, Fetcher data layer, Quick/Nimble + EarlGrey tests, central `Localizable.strings`. **When in doubt, copy Bus.**

---

## Build system

**Bazel (primary) + CocoaPods (secondary)**, both glob-driven. A new file dropped in the correct folder is auto-picked-up — no manifest edit. You manually manage only: new cross-module dep (add to `BUILD` `deps=[…]` AND `…podspec` `s.dependency`), new public entry point (`BusModule.swift`), new string (central `Localizable.strings`).

- Build a module: `bazel build //Traveloka/Modules/Bus:Bus`
- Or via Xcode: `xcodebuild -workspace Traveloka/Traveloka.xcworkspace -scheme <scheme> ...` (see `/xcode-build` in the iOS repo's own skills).

---

## After using this skill

List any pattern you observed in the code that this map doesn't cover as **Suggested skill updates** — the codebase evolves faster than this doc.
