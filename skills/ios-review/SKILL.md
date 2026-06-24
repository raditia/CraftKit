---
name: ios-review
description: Review an iOS bus/train diff against the MVVM-C contract — layer violations, Dependency-struct DI, Coordinator-only navigation, NSLocalizedString usage, SwiftLint compliance.
alwaysApply: false
---

**Commands:** `git diff <base>...HEAD`, `swiftlint lint --path <file>`, `grep -rn "pattern" Traveloka/Modules`
**Model:** everyday — escalate to `claude-opus-4-8` if the review surfaces an architectural conflict with non-obvious resolution

---

> **Core behaviors:** Read the actual changed files before commenting — never assume from filename. Push back on real issues, no sycophancy. Surface every violation. See `/using-agent-skills` and the pattern map in `/ios-patterns`.

---

**Context:** No `docs/context.md` (iOS is not EVPMR). Read the changed files plus, when a violation is unclear, the matching sibling feature in `Traveloka/Modules/<Module>/<Module>/` to confirm the established convention.

---

## What to check

### Layer boundaries (the core of MVVM-C)

- [ ] **ViewController** — forwards events + repaints only? **Flag** business logic, data fetching, computation, or navigation calls in the VC.
- [ ] **View (`…View.swift`)** — pure `UIView`, programmatic layout? **Flag** any state, ViewModel reference, or networking.
- [ ] **ViewModel** — holds all state/logic, returns nothing to UIKit directly? **Flag** any imported view type, any `import`-free direct `push/present/pop`, or `UIViewController` reference.
- [ ] **Contract** — both seam protocols (`…ViewModelProtocol` + `…ViewModelAction`) declared here, not scattered?
- [ ] **Fetcher** — all network/Realm access behind a `…FetcherProtocol`? **Flag** raw `TVLNetworkService` or `RealmManager` calls inside a ViewModel.

### Navigation

- [ ] ViewModel navigates **only** by firing `delegate?` callbacks — never calls `pushViewController`/`present` itself.
- [ ] Coordinator (not the VC/VM) owns all navigation and conforms to the screen's `…ViewModelDelegate`.
- [ ] Cross-module navigation routed through the app delegate (`AppCoordinatorNavigationApi`), not by importing another module's internals.

### Dependency injection

- [ ] Feature dependencies injected via the `…ViewModelDependency` struct (init injection), built by the Factory's `getProductionDeps()`.
- [ ] `@Injected` / `Factory` container used **only** for cross-cutting app singletons (metrics, etc.) — not for feature-local deps.
- [ ] No `…() ` singleton reached for directly inside the VM where a protocol dependency belongs.

### Strings / localization

- [ ] No hardcoded display text in View or VC — all via `NSLocalizedString`.
- [ ] Keys follow `<module>.<screen>.<widget>.<descriptor>`; new keys added to `Traveloka/Traveloka/<lang>.lproj/Localizable.strings`.

### Memory / correctness

- [ ] `action` and `delegate` are `weak` on the ViewModel — **flag** strong references (retain cycle: VC owns VM owns action→VC).
- [ ] `[weak self]` in escaping closures (Fetcher completions, async callbacks) where `self` is captured.
- [ ] No force-unwrap (`!`) on network/Realm results that can be nil.

### SwiftLint

- [ ] `swiftlint lint --path <file>` on every changed Swift file — zero violations (config `Traveloka/.swiftlint.yml`).
- [ ] No `// swiftlint:disable` without a documented reason on the same line.

### Tests

- [ ] ViewModel changes have matching Quick/Nimble specs in `Traveloka/Modules/<Module>/Tests/<Feature>/` — see `/ios-test`.
- [ ] New Fetcher protocols have a `…Mock` in `Traveloka/Modules/<Module>/Mocks/`.

---

## Output format

For each issue:
```
[SEVERITY] File:line — description
  Why: ...
  Fix: ...
```

`[ERROR]` = breaks the MVVM-C contract / retain cycle / correctness | `[WARNING]` = convention deviation, test gap | `[SUGGESTION]` = improvement worth considering.

Push back on real issues — do not soften findings. At the end, list patterns observed not covered by `/ios-patterns` as **Suggested skill updates**.
