---
name: eval-rubric
description: Weighted correctness rubric shared by /eval and the eval-judge agent. Criteria, weights, score anchors, the formula, and the floor rule. Spliced into both at sync time; never loaded always-on.
---

## Weighted correctness rubric

A deliverable is scored on five criteria, each `0-5`, each carrying a fixed weight. The weights are the contract: they encode what this repo thinks correctness *means*, so a run that nails the spec and skips the tests cannot score the same as one that did both.

| Criterion | Weight | Scored on |
|---|---:|---|
| Spec conformance | 35 | Every acceptance criterion in the feature's `docs/planning/` intent file is actually implemented, not approximated |
| Correctness | 25 | Logic holds on the inputs it claims to handle: edge cases, error paths, no crash or data-loss path |
| Pattern adherence | 20 | The platform contract holds: EVPMR layers (RN/web), MVP + Core (Android), MVVM-C (iOS) |
| Verification | 15 | Tests cover the changed paths and pass; type/lint gates clean |
| Simplicity | 5 | The ponytail rubric: nothing to delete, no reinvented stdlib, no speculative abstraction |

Weights sum to 100. `check.sh` asserts that, because a silently-broken sum produces a percentage that looks authoritative and is wrong.

### Score anchors

The same six anchors apply to every criterion, so two runs scored a week apart mean the same thing:

| Score | Means |
|---:|---|
| 5 | Fully met. Evidence cited, nothing outstanding |
| 4 | Met, with one cosmetic gap |
| 3 | Mostly met: one substantive gap that does not break the deliverable |
| 2 | Partly met: a substantive gap a reviewer would block on |
| 1 | Largely unmet |
| 0 | Not addressed at all, or actively wrong |

Every score below 5 names the specific gap that cost the points, with `file:line` evidence. A deduction with no evidence is not a deduction: per the provenance rule, an `[UNVERIFIED]` observation cannot carry a score below 3.

### The formula

```
Correctness % = Σ (score_i / 5 × weight_i)
```

Which is the weighted-score sum over total possible points, times 100. Worked example, matching the three-criterion figure this rubric generalizes:

```
Spec conformance   5/5 × 35 = 35.0
Correctness        4/5 × 25 = 20.0
Pattern adherence  4/5 × 20 = 16.0
Verification       3/5 × 15 =  9.0
Simplicity         5/5 ×  5 =  5.0
                            ───────
                              85.0%
```

### The floor rule

A weighted average hides a total miss: 85% can mean "solid everywhere" or "perfect except it does not do what was asked". So two floors override the band, and they are checked before the percentage is reported:

- **Any criterion at 0** blocks, whatever the total.
- **Spec conformance or Correctness at 2 or below** blocks, whatever the total.

### Verdict bands

| Total | Verdict |
|---|---|
| ≥ 90 | `PASS` |
| 75-89 | `PASS WITH GAPS` (name each gap; the author decides) |
| < 75 | `BLOCKED` |
| either floor tripped | `BLOCKED` (name the floor, not the band) |

### Unscorable criteria are gaps, not passes

When the input needed for a criterion is absent, that criterion is `n/a` and the run is `INCOMPLETE`. It is never scored `5` by default and never silently reweighted, because reweighting turns missing evidence into a higher percentage. This mirrors the skipped-agent doctrine: missing coverage is a gap, not a clean axis.

The common case is no intent file resolving, so Spec conformance is unscorable. Report the other four out of their 65 available points, say so explicitly, and leave the verdict `INCOMPLETE`:

```
Spec conformance: n/a  (no active intent file under docs/planning/, so no acceptance criteria to check)
Partial: 54.0 / 65 possible  →  INCOMPLETE
```

### Ledger row

Scored runs append one row to `docs/evals/ledger.md`, in the repo being worked on:

```
| date | run | commit | platform | spec | corr | pattern | verify | simp | % | verdict |
|------|-----|--------|----------|-----:|-----:|--------:|-------:|-----:|--:|---------|
| 2026-09-17 | parallel-build | a891629 | RN/web | 5 | 4 | 4 | 3 | 5 | 85.0 | PASS WITH GAPS |
```

The **evaluation success rate** is derived from those rows at read time (`PASS` rows / scored rows), never written into the file. A stored rate is a stale rate the moment the next row lands, and a derived one cannot drift.
