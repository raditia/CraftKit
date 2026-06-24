---
name: ios-test
description: Write or improve Quick + Nimble unit tests for an iOS bus/train ViewModel — mock dependencies via the Dependency struct and the …Action protocol, assert on captured values.
alwaysApply: false
---

**Commands:** `git diff <base>...HEAD`, `bazel test //Traveloka/Modules/<Module>:<Module>TestsBundle`, `swiftlint lint --path <file>`
**Model:** everyday — escalate to `claude-opus-4-8` if a ViewModel path can't be reached without refactoring the production code

> Triggered by: "write iOS tests", "test this view model", "add bus/train tests", "improve iOS coverage"

---

> **Core behaviors:** The unit under test is the **ViewModel** — never the View or VC. Tests must fail if the business rule changes, not just exercise getters. Never skip verification — specs must pass before done. See `/using-agent-skills` and `/ios-patterns`.

---

**Context:** No `docs/context.md`. Read the changed ViewModel(s) and one existing spec in `Traveloka/Modules/<Module>/Tests/<Feature>/` to copy the Quick/Nimble style and the existing mocks.

---

## Convention (observed in the codebase)

- Framework: **Quick + Nimble** (`QuickSpec`, `describe / context / it`, `expect(...) == ...`). No XCTest `func test…`, no swift-testing.
- Mocks live in `Traveloka/Modules/<Module>/Mocks/` and are compiled into both the test target and the EarlGrey target.
- Dependencies are injected by passing a hand-built `…ViewModelDependency` struct of `…Mock` objects.
- The View↔VM seam is tested by setting `viewModel.action = mockAction` and asserting on the values the mock captured.

---

## Test structure

```swift
import Nimble
import Quick
@testable import Bus

final class BusSearchFormViewModelTest: QuickSpec {
    override class func spec() {
        var viewModel: BusSearchFormViewModel!
        var mockAction: BusSearchFormViewModelActionMock!
        var dependency: BusSearchFormViewModelDependency!

        beforeEach {
            dependency = BusSearchFormViewModelDependency(
                searchSpecFetcher: BusSearchSpecFetcherMock(),
                featureValidator: BusFeatureValidatorMock())
            viewModel = BusSearchFormViewModel(dependency: dependency)
            mockAction = BusSearchFormViewModelActionMock()
            viewModel.action = mockAction
        }

        describe("onViewDidLoad") {
            it("pushes the default origin text so the field is never blank") {
                // Given an empty search spec (default mock)
                // When
                viewModel.onViewDidLoad()
                // Then — the rule: empty spec must surface the default, not ""
                expect(mockAction.actualOriginText) == expectedDefaultOriginText
            }
        }
    }
}
```

---

## Mock pattern

A mock conforms to the protocol, **captures** call args (for `…Action` / `…Delegate`) or **returns a fixture** (for `…Fetcher`):

```swift
final class BusSearchFormViewModelActionMock: BusSearchFormViewModelAction {
    private(set) var actualOriginText: String?
    func setOriginText(_ text: String) { actualOriginText = text }
}

final class BusDetailFetcherMock: BusDetailFetcherProtocol {
    func fetch(spec: BusSearchDetailSpec,
               completion: @escaping (BusSearchDetailResult) -> Void) {
        // load bundled JSON fixture, call completion synchronously
        completion(BusSearchDetailResult.fromFixture("busDetailMockJSON"))
    }
}
```

Reuse an existing mock from `Mocks/` before writing a new one. New Fetcher protocol → add its mock to `Mocks/` so other specs can reuse it.

---

## What to cover (per changed ViewModel)

Map cases from the diff — max 3 bullets per file, the rest emerge from running:
- Each **`…ViewModelProtocol` method** (the events): assert the resulting `action?` calls and/or `delegate?` calls.
- **Branching logic** in the VM: each path that produces a different `action`/`delegate` outcome.
- **Async/fetcher paths:** success and failure completion → correct `action` repaint or error handling.
- **Delegate fires:** when the VM should notify the Coordinator (`delegate?.…(self, didChange:)`), assert the mock delegate captured it.

Each `it` comment must state **why** the behavior matters (the rule being protected), not just what it asserts.

---

## Workflow

1. **Diff first** — `git diff <base>...HEAD --name-only`; touch only changed ViewModels.
2. **Read a sibling spec** in `Tests/<Feature>/` to match style + reuse mocks.
3. **Write specs** for every behavior path from the diff.
4. **Run** — all must pass:
   ```bash
   bazel test //Traveloka/Modules/<Module>:<Module>TestsBundle
   ```
   (Or run the module's test scheme in Xcode if Bazel is unavailable locally.) Fix failures — never skip or comment out an `it`.
5. **SwiftLint** — `swiftlint lint --path <each-new-test-file>`; fix all.
6. **Done** — report specs added, pass/fail count, and any VM path that was unreachable without a production refactor (flag, don't silently skip).

List testing patterns not covered above as **Suggested skill updates**.
