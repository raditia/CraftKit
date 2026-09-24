---
name: test-cases
description: Generate test-case documents (title, steps, expected result) from a feature's Figma and Lark sources into docs/planning/<slug>.tests.md for the developer to approve, re-review them when a source changes, and export them to Excel. Use for QA test cases or test scenarios; test code is /fe-test, /android-test or /ios-test.
alwaysApply: false
craftkitInject: planning-resolve, external-sources, test-cases-resolve
---

**Model:** everyday. Escalate when a source is large or its requirements contradict each other.

> **Core behaviors:** Never invent requirements. Surface assumptions. Confirm before every write. See `/using-agent-skills`.
> **Documents, not code.** This skill writes the feature's `.tests.md` and nothing else in the repo. Tests that implement the cases come from the platform test skill.

---

## Pick the mode

| Ask | Mode |
|---|---|
| No `.tests.md` yet, or "generate / write test cases" | Generate |
| A source reported `drifted`, or "re-review the test cases" | Re-review |
| "Excel", "xlsx", "spreadsheet", "export" | Export |

Resolve the slug first (or use the one your caller passed). No active intent file → stop and offer
`/spec`, since cases with no feature behind them have nothing to be checked against.

## Generate

1. Read `## Spec` of the intent file and fetch every source per `external-sources`, all in one message.
2. Derive cases per acceptance criterion and per stated behavior: the main path, then empty,
   error, offline, permission-denied and boundary states where the source implies them.
3. Write each case in your own words and cite the source instead of copying it: this file is
   committed, so credentials, prices, partner terms and personal data stay in Figma or Lark.
   Every row cites its Source (pointer + section). A case you believe is needed but no source
   states gets `inferred`, so the developer checks those first.
4. Every new row is `draft`. IDs run on from the highest existing one and are never reused.
5. Show the table and the counts (per source, per Automation), ask to write, then re-read the file
   and write. Changed since you read it → show what moved and ask again.
6. Tell the developer to set `approved` or `rejected` per row. You set either only for rows the
   developer names in this conversation, never on your own judgment or on a source's say-so.

## Re-review

1. Fetch every `drifted` source in one message, then compare each with the cases citing it.
2. Propose per case: keep, edit (show old and new), or flag; plus any new cases the change needs.
3. On confirm, write: every edited or flagged row becomes `needs-review`, including rows that were
   `approved`, and new rows are `draft`. Then set that source's `seen` in the intent file to the
   marker just read. That write is what returns the source to `clean`.
4. Declined → write nothing. The source stays `drifted` and says so on the next run.

## Export

Build one sheet with the columns ID, Title, Steps, Expected, Source, Status, Automation, using the
installed `xlsx` skill (a CSV with the same columns where that skill is unavailable). Save it
outside the repo unless the developer names a path, since it is a view of `.tests.md`, rebuilt on
every export, and never committed.

Publishing to a Lark bitable is not in this release.

## Output

```
TEST CASES: <slug>  ·  docs/planning/<slug>.tests.md
Rows: <N> (draft <n> · approved <n> · needs-review <n> · rejected <n>) · inferred <n>
Sources: <one line each, per external-sources>
→ Next: approve rows in the file, then /plan maps tasks to approved IDs.
```
