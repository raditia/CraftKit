# Context

**Branch:** main | **Base:** main | **Commit:** a891629b3e5a2c6fc9a10e319c02fced80b222be

_Backward sections (Summary, Key Changes) are filled by `/fe-context` from the diff once work starts._

<!-- BEGIN PLANNING: managed by /spec /plan /adr; preserved by /fe-context -->
## Planning (forward)
**Updated:** 2026-09-11T08:43:36Z · **By:** /spec

### Spec: unskippable gates + git-derived grounding

- **Objective:** Craftkit machinery degrades without saying so. The gates read a truncated
  turn; `sync.sh` compares no versions and downgrades an install silently; nothing detects that
  context read earlier has drifted; and source edits route to a skill only 38% of the time.
  Four fixes ship (F0, F2, F3, F5). Two candidates were built or planned and dropped on
  evidence (F1, F4), which is recorded here rather than quietly dropped.

- **Users & job:** The craftkit author plus every synced tool session (Claude, Cursor, Gemini,
  Codex). Job 1: reach the right skill without being told which. Job 2: never assert a fact
  from context that has drifted.

- **Evidence (T-1, 149 transcripts, 802 turns, read-only):** this replaces the assumption the
  first draft of this spec was built on.
  - `SlashCommand` tool_use: **0 occurrences**. Routing is carried by the `Skill` tool
    (222 calls) or not at all, so the gates watch the right tool.
  - 74 turns edited source; **28 (37.8%) carried a Skill call**. 24 declared no-match anyway,
    19 declared nothing.
  - Routed share of source-editing turns: **20.7% in 2026-08, 51.1% in 2026-09**, the window
    the enforcement gates landed in. Enforcement moved the number; injected prose did not
    change in that window.
  - The miss population is **contextless imperative continuations** ("apply the fixes",
    "continue", "can you make the popular countries > 10?"). The topic lives in the
    conversation, not the prompt, so prompt-token scoring cannot rank them. Of ~15 genuine
    misses, exactly one ("can you check this PR?") carried rankable vocabulary.

- **Success:** (each maps to an acceptance check below)
  1. A turn containing a Skill invocation is seen by both gates as one turn, including
     everything after the skill body arrives.
  2. `sync.sh` run from a tree older than the recorded install refuses and names the gap.
  3. A source-editing turn in a session that has never routed is caught; one whose session
     already routed is spared; a task-notification turn is never caught. Firing rate stays at
     or below the measured 18% baseline.
  4. Per-file drift is reported against an explicit baseline, with unreachable commits and
     dirty worktrees distinguished from clean, and consulted by the freshness step.
  5. Provenance labels exist as a rule, and `[UNVERIFIED]` cannot back an `[ERROR]` finding or
     a code edit.
  6. `bash check.sh` exits 0, `bash sync.sh` prints `Sync complete.`, and a second consecutive
     run reports `(up to date)` everywhere.

- **In scope:**
  - **F0 (done)** `hooks/craftkit-transcript.js:isUserTurn` treats an injected entry
    (`isMeta === true`) as not a turn boundary, covering both a skill body and stop-hook
    feedback. Fixtures in `check.sh` model the injected entry, which they previously did not.
  - **F1 (dropped)** Generating the routing hook's skill block from frontmatter. Both drift
    directions were already enforced: `sync.sh` aborts when a skill is missing from the hook,
    `check.sh` fails when the hook names a skill that does not exist. What still diverges is the
    hook's editorial content, which is judgment rather than derivable frontmatter.
  - **F2** `rules/grounding.md`: the three provenance labels
    (`[verified: <cmd|file:line>]`, `[from context.md @<sha>]`, `[UNVERIFIED]`) and the law that
    `[UNVERIFIED]` may not back an `[ERROR]` finding or a code edit.
  - **F2** Drift detector using `git diff --name-only <baseline> -- <paths>`, one command for
    all paths, which honors clean filters, covers staged and worktree states, and detects
    renames. Distinguishes clean, drifted, and cannot-verify, where an unreachable baseline
    (squash merge, rebase, amend, gc) reports cannot-verify rather than clean.
  - **F2 (dropped)** `hooks/gate-stale-context.js`, a PreToolUse gate on staleness. Built,
    measured, removed. See Key decisions.
  - **F2** Cold agents review only content handed to them, via `craftkitInject: grounding`
    rather than hand-copied rule text.
  - **F3** `sync.sh` records the installed version in `~/.craftkit-state/` and refuses a
    downgrade, naming both versions.
  - **F4 (dropped)** The `ponytail self-pass:` refusal was built, dogfooded for one turn, and
    removed. See Key decisions.
  - **F5** Extend `hooks/gate-skill-first.js` to cover the continuation case. Firing condition,
    chosen by measurement: a source-editing turn with no routing carrier asks **only when the
    session has not invoked a skill in any earlier turn**. Task-notification turns are skipped,
    since they are not prompts. Measured firing rate: **14 of 76 source-editing turns (18%)**,
    against 62% for the naive condition and 39% for a keyword filter. Record 18% as the
    baseline so a later pass can tell whether it improved.

- **Out of scope:**
  - **`triggers:` frontmatter on 36 skills.** Cut with the prefilter that was its only
    consumer. The drift fix needs no new key, since `name` and `description` already exist.
  - **Lexical prefilter and candidate ranking.** T-1 shows the misses carry no rankable tokens,
    so ranking cannot reach them, and an exclusionary variant would lower recall further.
  - **Narrowed answer-directly prose.** Prose is the instrument that already failed: the model
    receives the full skill tree always-on, a per-prompt injection, and three gates, and still
    missed 62% of source-editing turns.
  - **Prompt-to-expected-skill fixture eval, and the injected-byte-shrink criterion.** Both
    existed to measure the prefilter. With no prefilter the eval is vacuous (candidate set is
    every skill) and the byte criterion would pressure against its own vocabulary.
  - **Recording `SlashCommand` in `currentTurn`.** Zero occurrences in 149 transcripts.
  - **`/humanizer` on code comments.** Its contract is "rewrite, don't delete, cover everything
    the original covers", so it preserves the comment count a trim was meant to reduce; its patterns target
    prose essays; and it holds `Write`/`Edit`, so aimed at source it can alter code.
  - **A hard comment-to-code ratio as a blocking condition.** F0 measured 20 added comment lines
    to 2 added code lines with every comment protected by the rubric. The ratio is evidence.
  - **`git hash-object` as the drift comparand.** No `--path`, so clean filters are skipped and
    any `.gitattributes` `text=auto` or LFS entry yields permanent false drift. Also two
    commands per file where one covers all paths, a `stdlib:` hit.
  - **New prose in `karpathy-guidelines`.** The rule already says it; the gap is enforcement.
  - **A fourth Stop hook.** `gate-verify-on-stop` already detects shell-route and spawned-agent
    edits.
  - **Enforcing `flag self-pass:`** from `flag-safety`. Same gap, but detecting that a flag
    branch was touched is judgment while a missing line is mechanics. Deferred.
  - **Deleting `sync.sh:26` routing drift guard.** Generation makes it unable to fire, but it is
    pre-existing code and removal was not asked for.

- **Constraints:**
  - Routing hook: dependency-free Node, every prompt, ~100ms budget.
  - `sync.sh` and `check.sh`: bash 3.2 (macOS default), no bash 4+ features.
  - No prompt text leaves the machine.
  - Extend existing machinery, never parallel it.
  - Prose carries no em-dash outside the three wire-format exemptions (`check.sh`).
  - Every added rule or hook needs its README row and a `check.sh` check.
  - `CRAFTKIT_GATE=off` remains the single escape hatch for every gate.

- **Key decisions:**
  1. **Measure before building.** T-1 mined transcripts already on disk and deleted four of the
     five original F1 tasks. The first draft cut a "runtime declaration log" as out of scope
     without noticing the log already existed.
  2. **Enforcement over presentation.** The 20.7% to 51.1% shift tracks the gates landing, not
     any change in injected text. F5 follows that lever; the prefilter did not.
  3. **Gate the declaration, not the code.** Judging whether comments are excessive fires on
     correct work; checking that the turn declared its self-pass cannot false-positive. Known
     limit, shared with `gate-announce-honored`: a turn can declare "clean" over bloat.
  4. **Quotation is the known bypass.** `gate-announce-honored` needed line-anchoring plus
     fence-stripping for exactly this; `ponytail self-pass:` appears in 9 source files, so F4
     inherits both defenses and their negative fixtures.
  5. **F2's staleness gate cut on measurement, not argument.** Firing rate across the repos
     actually in use: `www` 8 of 41,433 source files (0.02%), `android-v3` 9 of 39,236
     (0.02%). Staleness itself is common (6.7% to 8.1% of files have an mtime past the doc),
     but a context doc names only ~8 files out of 41,000, so the conjunction the gate needs
     almost never lands. A third gate, a hook file, a README row, 7 fixtures and a per-edit
     stat, to catch 1 edit in 5,000, is decoration. What the measurement actually exposed is
     a `/fe-context` coverage problem: the docs describe almost nothing. That is a separate
     task, not this gate.
     Two measurement bugs preceded the number and both produced a comfortable 0%: an
     unreadable `transcript_path` made the gate fail open before deciding, and a sanity
     target that predated the doc proved nothing by not firing. A rate that confirms the
     hoped-for answer gets checked twice.
  6. **One command, not two per file.** `git diff --name-only <baseline> -- <paths>` replaces
     `hash-object` plus `rev-parse`, and handles filters, staging, and renames for free.
  7. **Derive, don't record.** The model-tier hook is the in-repo proof: hardcoded ids went
     stale, derived ids cannot.

- **Risks & open questions:**
  - *F5's condition leaks in both directions, and shipping it accepts that.* It fires on
    approval turns ("I'd go with your recommendation", "yes run it on emulator") where asking is
    noise, and it spares a genuine miss ("fix fe-rules path scoping") whose session had routed
    earlier for unrelated work. No mechanical condition separates these, because the
    discriminator is task identity, which a hook cannot judge. 18% was the lowest rate any
    tested condition reached while still catching the miss population.
  - *Keyword filtering was tested and rejected*, not skipped: a git-plumbing word list spared
    three real misses ("can you check this PR?", "apply the 4 shrinks", "update the throttle on
    this branch") because "PR", "push" and "branch" appeared incidentally.
  - *T-1's miss classification is judgment, not mechanics.* ~15 of 25 flagged turns are genuine
    misses; 5 are task notifications and ~5 are git plumbing.
  - *Two months and 74 source-editing turns is a small sample.* The direction is clear, the
    magnitude is not.
  - *`isMeta` is undocumented.* If it disappears, both gates revert to a truncated turn. Marked
    `ponytail:` and pinned by fixtures.
  - *F4 adds a second refusal to every code turn,* which must read as one message.
  - *Open:* should the comment ratio ever gate above some bound, or only inform.
  - *Open:* should `flag self-pass:` get the same treatment in a follow-up.
  - *Measurement caveat:* three T-1 passes counted 74, 56 and 76 source-editing turns, each
    including a different subset of shell-route detection. Proportions are stable, absolute
    counts are not comparable across passes. The 18% baseline comes from the 76-turn pass.

- **Acceptance:**
  - [x] Given a transcript where a `Skill` tool_use is followed by an `isMeta` skill body and
        then an `Edit`, both gates pass; with the `Skill` call removed, the skill gate still
        asks; with `isMeta` stripped, the new checks fail.
  - [ ] Given a skill's `description` edited without regenerating, `check.sh` fails reporting
        the hook block stale; regenerating twice yields no diff.
  - [ ] Given an install recorded newer than the tree being synced from, `sync.sh` refuses and
        names both versions; equal or newer proceeds; a first run with no recorded version
        proceeds and records one.
  - [x] Given one file edited several times in a turn, the refusal counts it once.
  - [x] Given any refusal from the stop gate, the message names `CRAFTKIT_GATE=off`.
  - [ ] Given a source-editing turn in a session with no earlier `Skill` call, the skill gate
        asks; given one whose session routed in an earlier turn, it does not; given a
        task-notification turn, it does not.
  - [ ] Given the session-scope lookback removed, the continuation fixtures fail, so the scope
        cannot pass for the wrong reason.
  - [ ] Given a baseline commit and one file edited since, the detector names that file; with
        none edited it reports clean; with an unreachable baseline or outside a git repo it
        reports cannot-verify, never clean.
  - [ ] Given a file renamed since the baseline, the detector reports it without fataling.
  - [x] Given the staleness gate measured at a 0.02% firing rate, it is cut rather than
        shipped; see Key decisions.
  - [ ] Given `rules/grounding.md` added, README carries its row, `check.sh` covers it, and all
        14 `agents/*.md` carry the injected body after sync.
  - [ ] `bash check.sh` exits 0; `bash sync.sh` prints `Sync complete.`; a second consecutive
        `sync.sh` reports `(up to date)` everywhere.

### Task Plan
**Updated:** 2026-09-11T08:36:45Z · **By:** /plan

| ID | Task | Acceptance | Depends on | Executes via |
|----|------|-----------|-----------|--------------|
| T0 | **DONE** `isUserTurn` ignores injected (`isMeta`) entries so a skill body no longer truncates the turn | 5 `check.sh` assertions pass; all 3 positive ones fail with the fix removed | none | `/fix` (done) |
| T1 | **CUT** Generate the routing hook's skill block from frontmatter | Both drift directions are already enforced: `sync.sh:60-68` aborts when a skill is missing from the hook, `check.sh:175` fails when the hook names a skill that does not exist. What is left diverging is the hook's editorial content (groupings, tiebreakers, `/define chains interview→spec→plan`), which is judgment, not derivable from `name` + `description`. Generating it would replace curated routing guidance with a name dump | none | none |
| T2 | `rules/grounding.md`: three provenance labels and the `[UNVERIFIED]` law, plus README row and a `check.sh` check | README row present; `check.sh` covers it; installs to all 4 tools; second sync a no-op | none | `/build` |
| T3 | Drift detector on `git diff --name-only <baseline> -- <paths>`, distinguishing clean, drifted, cannot-verify (unreachable baseline, non-git, renames) | Behavioral `check.sh`: edited named, unedited clean, unreachable baseline and non-git both cannot-verify, rename reported without fatal | none | `/build` |
| T4 | **CUT** staleness gate. Measured at 0.02% firing (8/41,433 in `www`, 9/39,236 in `android-v3`): staleness is common but context docs describe ~8 files of 41,000, so the conjunction never lands. Kept from the attempt: `onceInTurn` extracted and shared, the rules-README-row check, and a portable drift instruction | n/a | none |
| T5 | Point the three `*-context` skills and Standard context loading at the detector, recording an explicit baseline in the doc header | A regenerated doc carries a baseline the detector accepts; the freshness step consults it | T3 | `/build` |
| T6 | Opt all 14 `agents/*.md` into `craftkitInject: grounding` so cold agents carry the live rule instead of a copy | `craftkitInject` sources resolve; installed agents carry the body; second sync a no-op | T2 | `/build` |
| T7 | `sync.sh` version guard: record the installed version in `~/.craftkit-state/`, refuse a downgrade naming both versions | Behavioral `check.sh`: older-over-newer refuses; equal or newer proceeds; first run records | none | `/fix` |
| T8 | **DROPPED** self-pass refusal in `gate-verify-on-stop.js`. Built, dogfooded one turn, removed: it cannot tell a real rubric scan from a recitation, so it taxed every code turn for a signal that reads as compliance either way. The two defects it exposed (repeat-edit counting, escape hatch unnamed) were bugs in the verification reason too and are kept | `check.sh`: one file edited four times counts once; every refusal names `CRAFTKIT_GATE=off` | none | `/fix` (done) |
| T9 | **DROPPED** with T8 (comment-to-code counts in the refusal message) | n/a | n/a | none |
| T10 | **DROPPED** with T8 (self-pass fixtures) | n/a | n/a | none |
| T11 | Extend `gate-skill-first.js` to session scope: ask on a source-editing turn only when no earlier turn in the session invoked a skill; skip task-notification turns | Behavioral `check.sh`: session-never-routed asks; session-routed-earlier does not; notification turn does not; removing the lookback makes those fixtures fail | none | `/fix` |
| T13 | Close the `stop_hook_active` bypass while keeping the no-infinite-loop property: a second stop attempt currently passes every Stop gate with nothing emitted | Behavioral `check.sh`: a turn blocked once and retried unchanged is still refused; a turn blocked once and then corrected passes; no fixture loops more than a bounded number of attempts | none | `/fix` |
| T12 | Release: version bump in `package.json` and the README header, plus a matching `CHANGELOG.md` section | `check.sh` version-consistency check green; `sync.sh` clean and idempotent | T1-T11, T13 | `/parallel-ship` |

**Parallelizable now:** T1, T2, T3, T7, T8, T11
**Critical path:** T3 → T4 → T12, and T8 → T9 → T12 (3 deep)

**Sequencing note:** T8 lands early despite having no dependents. It makes every later task's
own self-pass enforceable, so building the rest first means building it under the advisory
regime this change exists to end.

**T13 came out of the T8 review and outlived it.** With T8 dropped its severity falls, but it
still holds against the verification and announce gates: `stop_hook_active` passes a second
stop attempt with no check at all, and `check.sh` codifies that as required behavior, so a
turn blocked for skipping verification can emit nothing and stop again. The constraint on
any fix is the reason the flag exists, which is that a gate refusing its own retry forever
is unusable.

**T11's bound is now measured, not assumed:** session-never-routed fires on 18% of
source-editing turns, against 62% naive and 39% keyword-filtered. The leak in both directions
is documented under Risks and accepted, because no mechanical condition can judge task
identity. Re-measure against the 18% baseline after it ships.

### Decisions
_(appended by /adr)_
<!-- END PLANNING -->
