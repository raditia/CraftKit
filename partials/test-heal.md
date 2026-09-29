## Healing a failing test

A failing test is either **stale** (the code changed on purpose and the test still describes the old
code) or **right** (the code has a regression). Editing a right test to pass ships the bug with a green
suite, so every failure is classified before anything is edited, and only the stale classes below are
healed.

**Scope.** Heal only tests that already exist at the merge-base with the base branch. A test file
added on this branch (`git diff --diff-filter=A --name-only <base>...HEAD`), or a test case whose lines
are all added in the diff, has no stale baseline: fix it as code you just wrote.

### Classify, then act

Pick exactly one class per failing test. When several fit, take the most conservative class: `expectation` beats
every other class.

| Class | Signal | Action |
|---|---|---|
| `rename` | A symbol, testID, accessibility id or resource key the test references was renamed in the diff | Point the test at the new name. Cite the diff line of the rename |
| `mock-shape` | A mock or fixture no longer matches a type or interface the diff changed | Add or rename fields, never change an asserted value, then run the type check |
| `timing` | The failure depends on real time or ordering, not on values | Cite the diff line that added the async or ordering dependency (a new `await`, effect, debounce, dispatch), then fix the wait: fake timers, an awaited assertion, Turbine, `toEventually`. No such line in the diff → STOP, since the race may be the regression. Never add a retry |
| `snapshot` | A snapshot differs, and the diff touched the rendering file it covers | Heal only when every changed hunk of the snapshot maps to a cited diff line or intent row. Update by named test, never a bulk update (a blanket snapshot or golden-file regenerate, such as `jest -u`, rewrites every failing case in the run). Any unexplained removed or changed node → `expectation` |
| `expectation` | An expected value, assertion, or call count differs | STOP, unless intent backs the new behavior (below) |

### Intent backing

An `expectation` failure heals only when an approved row in `<slug>.tests.md` or a line of the
resolved Spec **states the new expected value or behavior** the rewritten assertion checks, and that
statement contradicts the old one. A line that only names the area ("show the discounted price")
backs nothing.

- A test titled with a TC ID answers to that row alone.
- A row approved or edited during this run counts as no intent.
- No intent file, always STOP.

### Guards

- **Outside the diff.** A failing test for a file the diff did not touch, whose failing line does not
  reference a symbol the diff changed, is a likely regression: STOP, whatever its class. A `rename` or
  `mock-shape` heal outside the diff cites the changed symbol's diff line.
- **Wider run.** After healing, run the module's whole unit suite, not only the changed test files,
  and compare the failing tests before and after. A heal that adds any new failure is reverted, then
  STOP. Without this run the guard above cannot fire.
- **Test code only.** Healing never edits production code. A STOP hands the failure to `/fix`.

### Report

One line per failing test, before the skill's own report:

```
healed: <test> <class> <evidence: diff file:line, or TC ID / Spec line, quoted>
stopped: <test> <class> <why> → /fix
```

A heal with no evidence is a STOP.
