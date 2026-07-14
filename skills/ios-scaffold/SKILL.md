---
name: ios-scaffold
description: Scaffold a new iOS feature screen in a modular monorepo following the MVVM-C contract — Contract + ViewController + View + ViewModel + Factory + Fetcher stub. Bazel/CocoaPods globs auto-wire new files.
alwaysApply: false
---

**Commands:** `ls Modules/<Module>/<Module>/<Feature>`, `grep -rn "pattern" Modules`, `swiftlint lint --path <file>`
**Model:** cheapest — `claude-haiku-4-5`. Escalate to everyday if the screen needs state/effect orchestration not covered by MVVM-C

---

> **Core behaviors:** Surface assumptions before generating. Copy a real sibling feature — never invent structure. Don't pre-split into sub-views speculatively. See `/using-agent-skills` and the pattern map in `/ios-patterns`.

---

**Context:** No `docs/context.md` (iOS is not EVPMR). **Mandatory first step:** read one existing sibling feature in `Modules/<Module>/<Module>/<Feature>/` to copy exact naming, imports, and ObjC/Swift split.

---

## Step 1 — Understand context

State assumptions before generating:
```
ASSUMPTIONS I'M MAKING:
1. Module: [target module]
2. Feature name: [PascalCase, e.g. DetailSelection]
3. File prefix: <Module><Feature> → e.g. <Prefix>
4. Sibling I'm copying from: [path to an existing feature folder]
5. Contract language: [.h ObjC / .swift] — match the module's dominant style
6. Has its own screen (gets a Coordinator hook)? [yes/no]
→ Correct me now or I'll proceed with these.
```

Read the sibling folder first. Prefer copying the newest/cleanest sibling in the module, then adjust to the module's ObjC/Swift split if needed.

---

## Step 2 — Create the feature folder

All files in `Modules/<Module>/<Module>/<Feature>/`. Naming: **`<Module><Feature><Role>`** (`<Prefix>` = `<Module><Feature>`).

### `<Prefix>Contract.h` (or `.swift` if module is Swift-forward)
The View↔VM seam — two protocols:
```objc
@protocol <Prefix>ViewModelAction <NSObject>
// callbacks the VM fires to repaint the view: setX:, openY:
@end

@protocol <Prefix>ViewModelProtocol <NSObject>
@property (nonatomic, weak) id<<Prefix>ViewModelAction> action;
- (void)onViewDidLoad;
// + one method per UIKit event the VC forwards
@end
```

### `<Prefix>ViewController.swift`
Thin UIKit VC — forward and repaint only, **no logic**:
```swift
final class <Prefix>ViewController: BaseViewController {
    private let viewModel: <Prefix>ViewModelProtocol
    private lazy var thisView = <Prefix>View()

    init(viewModel: <Prefix>ViewModelProtocol) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        self.viewModel.action = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() { view = thisView }
    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.onViewDidLoad()
    }
}

extension <Prefix>ViewController: <Prefix>ViewModelAction {
    // implement each callback → mutate thisView
}
```

### `<Prefix>View.swift`
`UIView`, programmatic layout (constraint DSL + the design-system kit). **No state, no VM reference:**
```swift
final class <Prefix>View: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    private func setupView() { /* add subviews + constraints */ }
}
```

### `<Prefix>ViewModel.swift`
All state + logic + tracking. `weak action` + `weak delegate`:
```swift
final class <Prefix>ViewModel: NSObject, <Prefix>ViewModelProtocol {
    weak var action: <Prefix>ViewModelAction?
    weak var delegate: <Prefix>ViewModelDelegate?
    private let dependency: <Prefix>ViewModelDependency

    init(dependency: <Prefix>ViewModelDependency) {
        self.dependency = dependency
        super.init()
    }
    func onViewDidLoad() { /* load via dependency.fetcher, then action?.setX(...) */ }
}
```
If the screen navigates onward, declare `<Prefix>ViewModelDelegate` (in the Contract) with the callbacks the Coordinator will implement.

### `<Prefix>Factory.swift`
Builds VM + VC, declares the Dependency struct:
```swift
struct <Prefix>ViewModelDependency {
    let fetcher: <Prefix>FetcherProtocol
    static func getProductionDeps() -> Self {
        Self(fetcher: <Prefix>Fetcher())
    }
}

enum <Prefix>Factory {
    static func makeViewController(
        dependency: <Prefix>ViewModelDependency = .getProductionDeps(),
        delegate: <Prefix>ViewModelDelegate?) -> <Prefix>ViewController {
        let vm = <Prefix>ViewModel(dependency: dependency)
        vm.delegate = delegate
        return <Prefix>ViewController(viewModel: vm)
    }
}
```

### `Fetcher/<Prefix>Fetcher.swift`
Data layer behind a protocol — stub the methods the VM needs:
```swift
protocol <Prefix>FetcherProtocol {
    func fetch(completion: @escaping (Result<<Model>, ErrorResponse>) -> Void)
}
final class <Prefix>Fetcher: <Prefix>FetcherProtocol {
    func fetch(completion: @escaping (Result<<Model>, ErrorResponse>) -> Void) {
        // shared network service POST/GET, or local DB read
    }
}
```

---

## Step 3 — Wire navigation (only if the screen is reachable)

The VM does NOT navigate. Add the new screen to the module's Coordinator:
1. Make the Coordinator conform to `<Prefix>ViewModelDelegate`.
2. Add a private `navigateTo<Feature>(...)` helper that calls `<Prefix>Factory.makeViewController(delegate: self)` and `pushViewController`.
3. If reachable from another module/deeplink, add a `static` entry to `<Module>Module.swift` (only if the module has a façade).

State the wiring you did or skipped — don't silently leave a screen unreachable.

---

## Step 4 — Strings

No resource file. Add keys to `App/en.lproj/Localizable.strings` (and other `.lproj` if the team requires), reference via:
```swift
NSLocalizedString("<module>.<screen>.<widget>.<descriptor>", comment: "<design link or context>")
```
Never hardcode display text in the View or VC.

---

## Step 5 — Quality rules

- VC and View hold **no business logic** — all logic in the VM.
- VM never imports a view type or navigates directly.
- One responsibility per file. Split a View into sub-views only when it genuinely grows complex — not speculatively.
- Match the sibling's exact import style and ObjC/Swift split. Don't introduce SwiftUI unless copying a `…V2`/`…Revamp` sibling that already uses it.

---

## After generating

- [ ] `swiftlint lint --path <each-new-swift-file>` — zero violations (config: `.swiftlint.yml`)
- [ ] New files sit in the correct folder so Bazel/CocoaPods globs pick them up — no `BUILD`/`podspec` edit needed unless you added a cross-module dependency
- [ ] If you added a cross-module dep: update both `Modules/<Module>/BUILD` (`deps=[…]`) and `<Module>.podspec` (`s.dependency`)
- [ ] Build check (optional, slow): `bazelisk build //Modules/<Module>:<Module>`
- List each file created with its path
- Note the sibling you copied and any naming/wiring assumptions
- List patterns observed not covered by `/ios-patterns` as **Suggested skill updates**
