---
name: eval
description: Score a finished agentic run into a weighted correctness percentage. Spawns the eval-judge agent over the deliverable, recomputes the arithmetic deterministically, appends the score to docs/evals/ledger.md, and derives the running evaluation success rate. Use after a build or ship run, or when asked "how correct was that", "score this run", "what is our success rate".
alwaysApply: false
craftkitInject: eval-rubric, planning-resolve
---

**Commands:** `rtk git diff`, `rtk git rev-parse --short HEAD`, `awk` for the weighted sum
**Model:** cheapest tier for the orchestration (see the plan-aware Model routing table in `using-agent-skills`). Escalate the judge itself to the escalate tier when the score gates a merge or a release, and for an irreversible gate run two judges through the fusion-panel process rather than trusting one.

---

## Trigger

User says: "score this run", "how correct was that", "eval this", "what is our correctness", "what is our success rate", or invokes `/eval`. Also offered as a tail of `/parallel-build` and `/parallel-ship`.

---

## Step 1: Gather the four inputs

The judge is cold, so everything it scores must be passed inline. Run the first three in parallel:

```bash
rtk git remote show origin | grep 'HEAD branch'     # base
rtk git rev-parse --short HEAD                      # commit for the ledger row
rtk git diff <base>...HEAD                          # the deliverable
```

Then the acceptance criteria: resolve the active intent file per the partial above and read its `## Spec`. No intent file means Spec conformance is unscorable, which the rubric handles as `n/a` plus `INCOMPLETE`. Do not substitute the commit messages or your own reading of intent for acceptance criteria, because a spec you invented is a spec the run cannot fail.

Gate results come from the run being scored: the `PHASE 1` block of a `/parallel-build` or `/parallel-ship` that just finished, or, when `/eval` is invoked standalone, run the platform's type/lint/test row yourself first. Verification cannot be scored from a diff alone.

---

## Step 2: Spawn the judge

One `eval-judge` agent, with this user message:

```
RUN: <parallel-build | parallel-ship | standalone>
PLATFORM: <RN/web | Android | iOS>
COMMIT: <short sha>

ACCEPTANCE CRITERIA:
<the intent file's ## Spec, verbatim, or: none found>

GATES:
type/build: PASS | FAIL | n-a
lint:       PASS | FAIL
test:       PASS | FAIL (N tests, M% coverage)

DIFF:
<full diff>
```

---

## Step 3: Recompute the arithmetic

Take the judge's five `0-5` scores and compute the total yourself. A judge is for picking anchors, which is judgment; the weighted sum is arithmetic, and arithmetic belongs in code:

```bash
awk -v s=5 -v c=4 -v p=4 -v v=3 -v x=5 \
  'BEGIN{printf "%.1f\n", (s*35 + c*25 + p*20 + v*15 + x*5)/5}'
```

If your total disagrees with the judge's, yours stands and the judge's arithmetic slip is worth one line in the output. Then apply the floor rule and the band from the rubric, in that order, since a tripped floor overrides the band.

---

## Step 4: Append the ledger row

Append the rubric's row to `docs/evals/ledger.md` in the repo being worked on, creating the file with its header when absent. Append only: never rewrite or re-score an existing row, because the point of the ledger is that a regression stays visible.

An `INCOMPLETE` run still gets a row, with `n/a` in the unscorable columns and no percentage. A row with no percentage is excluded from the success rate rather than counted as a failure.

---

## Step 5: Derive the success rate and report

Read the rows back and compute `PASS rows / rows carrying a percentage`. Derive it every time; never store it.

```
CORRECTNESS: 85.0%   (spec 5 · corr 4 · pattern 4 · verify 3 · simp 5)
FLOOR: clear
VERDICT: PASS WITH GAPS

TOP FIX: <highest-value deduction and what recovers it>

LEDGER: docs/evals/ledger.md · 12 scored runs
SUCCESS RATE: 75.0%  (9 / 12 at PASS)
TREND: last 5 runs 80.0% → previous 5 at 60.0%
```

Omit the `TREND` line until there are 10 scored rows, since a trend over 3 runs is noise wearing a percentage.

---

## Threshold gating

The rubric's bands are the default. A repo that wants a hard gate sets its own threshold in `docs/evals/ledger.md` under a `**Threshold:**` line in the header, and `/eval` reads it in place of the 90 boundary. That is the CI-gate shape: a prompt change or model upgrade that drops the score below the threshold is a quality regression, and the run reports `BLOCKED` rather than a passing percentage with a footnote.

`/eval` reports the verdict. It does not block a merge or revert anything, because deciding what a 78% means is the author's call, not the scorer's.

---

## Boundaries

Read-only on source. The only file it writes is `docs/evals/ledger.md`. It does not fix findings, does not re-run the build, and does not score the agents' process (see `eval-judge`, which scores the deliverable only). To act on what it found, route to the skill that owns the losing criterion: `/fe-test` for Verification, the platform's review skill for Pattern adherence, `/ponytail-review` for Simplicity.
