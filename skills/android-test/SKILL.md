---
name: android-test
description: Write or improve JUnit + MockK unit tests for an Android Presenter (or StateFlow ViewModel) — mock injected collaborators, spy the ViewModel, assert on emitted state and events. Turbine for Flow.
alwaysApply: false
---

**Commands:** `git diff <base>...HEAD`, `./gradlew :<module>:testGeneralDebugUnitTest`, `./gradlew :<module>:lintGeneralDebug`
**Model:** everyday — escalate to `claude-opus-4-8` if a Presenter path can't be reached without refactoring the production code

> Triggered by: "write Android tests", "test this presenter", "add tests for this screen", "improve Android coverage"

---

> **Core behaviors:** The unit under test is the **Presenter** (or a `StateFlow` ViewModel) — never the Activity/Fragment. Tests must fail if the business rule changes, not just exercise getters. Never skip verification — tests must pass before done. See `/using-agent-skills` and `/android-patterns`.

---

**Context:** No `docs/context.md`. Read the changed Presenter(s) and one existing sibling test in `src/test/...` to copy the MockK style and shared fixtures.

---

## Convention (observed in the codebase)

- Framework: **JUnit4 + MockK** (`mockk`, `spyk`, `every`, `verify`, `coEvery`/`coVerify` for suspend). **Turbine** for `StateFlow`/Flow. `kotlinx-coroutines-test` for coroutine control.
- Test method names are backticked human-readable phrases: `` fun `sets title when request succeeds`() ``.
- Location mirrors main source exactly: `src/test/java/.../<Prefix>PresenterTest.kt` next to `src/main/java/.../<Prefix>Presenter.kt`.
- Construct the Presenter directly (not via Dagger), mock every injected collaborator, spy a bare ViewModel to assert on emitted state/events.
- Shared fixtures/rules come from the `:shared-test` module.

---

## Test structure

```kotlin
class <Prefix>PresenterTest {
    private val repository: <Feature>ApiRepository = mockk()
    private val viewModel = spyk(<Prefix>ViewModel())
    private lateinit var presenter: <Prefix>Presenter

    @get:Rule val mainDispatcherRule = MainDispatcherRule()   // from :shared-test

    @Before fun setup() {
        presenter = <Prefix>Presenter(repository).apply { attach(viewModel) }
    }

    @Test
    fun `sets title when request succeeds`() = runTest {
        // Given
        coEvery { repository.requestX(any()) } returns XResponse(title = "Expected")
        // When
        presenter.onViewCreated()
        // Then — the rule: a successful load must surface the server title, not a blank
        assertEquals("Expected", viewModel.title)
    }
}
```

### StateFlow ViewModel (newer screens) — Turbine

```kotlin
@Test
fun `emits Loading then Content`() = runTest {
    coEvery { repository.requestX(any()) } returns XResponse(...)
    viewModel.state.test {
        viewModel.load()
        assertEquals(State.Loading, awaitItem())
        assertEquals(State.Content(...), awaitItem())
        cancelAndConsumeRemainingEvents()
    }
}
```

---

## Mock pattern

- `mockk()` for collaborators; `coEvery { … } returns …` for suspend functions.
- `verify { viewModel.postEvent(match { it.type == NAVIGATE }) }` to assert one-off effects.
- Reuse fixtures from `:shared-test` before writing new ones.

---

## What to cover (per changed Presenter)

Map cases from the diff — max 3 bullets per file, the rest emerge from running:
- Each **public Presenter method** (the events): assert the resulting VM state + queued events.
- **Branching logic:** each path that produces a different VM outcome.
- **Async/repository paths:** success and failure → correct VM state or error event.
- **Effect emissions:** navigate/close/toast queued when the rule requires it.

Each test must protect a **rule** (why the behavior matters), not just assert a getter.

---

## Workflow

1. **Diff first** — `git diff <base>...HEAD --name-only`; touch only changed Presenters.
2. **Read a sibling test** to match MockK style + reuse `:shared-test` fixtures.
3. **Write tests** for every behavior path.
4. **Run** — all must pass:
   ```bash
   ./gradlew :<module>:testGeneralDebugUnitTest
   ```
   (Or via the Fastlane unit-test lane with coverage.) Fix failures — never `@Ignore` a test to go green.
5. **Lint** — `./gradlew :<module>:lintGeneralDebug`; fix all.
6. **Done** — report tests added, pass/fail count, and any Presenter path unreachable without a production refactor (flag, don't silently skip).

List testing patterns not covered above as **Suggested skill updates**.
