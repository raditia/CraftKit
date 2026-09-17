# Context

**Branch:** main | **Base:** main | **Commit:** a891629b3e5a2c6fc9a10e319c02fced80b222be

_Backward sections (Summary, Key Changes) are filled by `/fe-context` from the diff once work starts._

<!-- BEGIN PLANNING: managed by /spec /plan /adr; preserved by /fe-context -->
## Planning (forward)
**Updated:** 2026-09-17T00:00:00Z · **By:** /spec

### Spec: weighted correctness scoring for agentic runs

- **Objective:** turn the output of a craftkit workflow run into a single tracked number, so a
  rule edit, a partial split, or a model upgrade can be shown to have made the output better or
  worse instead of argued about.
- **Users & job:** the engineer who just ran `/parallel-build` or `/parallel-ship` and wants to
  know how much of the deliverable was right, plus the maintainer of this repo who wants a
  regression signal across releases.
- **Success:**
  - `/eval` prints a correctness percentage, five per-criterion scores, a floor result, and a
    verdict, for a run it was handed.
  - A scored run appends exactly one row to `docs/evals/ledger.md` in the target repo.
  - The evaluation success rate is computed from those rows at read time and appears in no
    file, so it cannot be stale.
  - A run with no acceptance criteria available reports `INCOMPLETE`, never a passing score.
- **In scope:** the rubric contract, one cold judge agent, the `/eval` orchestration skill, the
  ledger format, routing, and the opt-in offer at the tail of the two build/ship workflows.
- **Out of scope:**
  - The golden-dataset harness (a fixture repo, ~50 representative tasks, a CI runner, a
    release gate). Deferred deliberately: it needs a target fixture repo and a model API budget
    that do not exist here, and it needs stable per-run scores to calibrate against, which the
    ledger has to accumulate first.
  - Scoring the agents' process (which agents ran, whether they ran in parallel). One axis, one
    question: is the deliverable correct.
  - Blocking a merge or reverting anything. `/eval` reports; the author decides.
  - Any change to the 14 existing agents or to how the classifier selects them.
- **Constraints:**
  - Weights are a contract, so they live in one injected partial and every copy is gated.
  - The judge is cold, so everything it scores is passed inline; it may not read the repo to
    replace content the caller should have handed it.
  - bash 3.2, and the em-dash prose gate, since this is craftkit source.
- **Key decisions:**
  - Scope is per-run judge plus an accumulating ledger, not a golden-dataset harness (user
    choice, offered as three options).
  - The judged object is the deliverable against acceptance criteria, not agent output quality
    (user choice).
  - Floors override the verdict band, because a weighted average is built to hide the case
    "perfect except it does not do what was asked".
  - An unscorable criterion is `n/a` plus `INCOMPLETE`, never reweighted, since reweighting
    converts missing evidence into a higher score.
  - The success rate is derived, never recorded, per the `grounding` rule's preference for
    derivation over a cache with no invalidation story.
  - The agent is `eval-judge`, not `judge`: `judge` already names the fusion-panel synthesis
    role in `using-agent-skills` model routing.
- **Acceptance:**
  - [ ] `bash check.sh` exits 0, including a new check that the rubric weights sum to 100 in
        all three places they are written, and that both hosts still inject the partial.
  - [ ] That new check fails before it passes, demonstrated per branch.
  - [ ] `bash sync.sh` prints `Sync complete.`, and a second consecutive run reports
        `(up to date)` everywhere.
  - [ ] The rendered rubric is present in the installed artifact for all four tools.
  - [ ] The routing hook advertises `/eval` on a real cwd.
  - [ ] README documents the new skill and the new agent; version agrees across
        `package.json`, the README header, and the newest `CHANGELOG.md` section.

### Task Plan
**Updated:** 2026-09-17T00:00:00Z · **By:** /plan

All tasks below are complete; the acceptance evidence is the `check.sh` + `sync.sh` run recorded
in the v1.38.0 `CHANGELOG.md` section. Retroactive record, so intent is readable without
reverse-engineering the diff.

| ID | Task | Acceptance | Depends on | Executes via |
|----|------|-----------|-----------|--------------|
| T1 | Conflict-check `judge` and `/eval` against rules/skills/commands/agents | Collision named and resolved before any file is written | none | repo authoring rules (`CLAUDE.md`) |
| T2 | Write `partials/eval-rubric.md`: criteria, weights, anchors, formula, floors, bands, ledger row | Weights sum to 100; anchors apply to every criterion | T1 | direct authoring |
| T3 | Write `agents/eval-judge.md` injecting `eval-rubric` + `grounding-claims` | `check.sh` resolves the inject; rendered body carries both partials | T2 | direct authoring |
| T4 | Write `skills/eval/SKILL.md`: gather, spawn judge, recompute in `awk`, append ledger, derive rate | Arithmetic recomputed outside the model; ledger append-only | T2 | direct authoring |
| T5 | Advertise `/eval` in `hooks/craftkit-routing.js` | Hook output on a real cwd names `/eval`; sync drift guard passes | T4 | direct authoring |
| T6 | Route `/eval` in `rules/using-agent-skills.md`: tree entry + tiebreaker vs `/parallel-review` | Both channels agree with the hook | T5 | direct authoring |
| T7 | Offer `/eval` at the tail of `parallel-build` and `parallel-ship`, passing gate results through | Offer is opt-in, never auto-run, never blocks | T4 | direct authoring |
| T8 | Add `check.sh` check 31: weights sum to 100 across partial, README, and the `awk` line; both hosts inject | Check fails before it passes on each of three branches | T2, T3, T4 | `bash check.sh` |
| T9 | README sync (TOC, section, skills table, agents table), `CLAUDE.md` check inventory, v1.38.0 across three files | `check.sh` README-coverage and version-agreement checks pass | T3, T4, T8 | repo README sync matrix |
| T10 | Verify distribution: `check.sh` clean, `sync.sh` twice, rendered rubric in all four tools | Second sync reports `(up to date)` everywhere | T9 | `bash sync.sh` |

Critical path: T1 → T2 → T4 → T8 → T9 → T10, six deep. T5/T6/T7 parallelize off T4.

### Decisions
- [ADR-0001](adr/0001-intent-keyed-per-feature.md) · intent lives in one file per feature under `docs/planning/`, because a single PLANNING slot lets one feature destroy another's spec · Accepted 2026-09-17
- [ADR-0002](adr/0002-derived-context-is-derived.md) · git-derived context is derived at read time and never stored, because a cache keyed on commit equality cannot see staged work and hits near zero on an active branch · Accepted 2026-09-17
<!-- END PLANNING -->
