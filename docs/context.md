# Context

**Branch:** main | **Base:** main | **Commit:** a891629b3e5a2c6fc9a10e319c02fced80b222be

_Backward sections (Summary, Key Changes) are filled by `/fe-context` from the diff once work starts._

<!-- BEGIN PLANNING: managed by /spec /plan /adr; preserved by /fe-context -->
## Planning (forward)
**Updated:** 2026-09-11T08:36:45Z · **By:** /spec

### Spec: unskippable gates + git-derived grounding

- **Objective:** Five pieces of craftkit machinery degrade without saying so. The gates read a
  truncated turn; `sync.sh` compares no versions and downgrades an install silently; the
  `ponytail self-pass:` line is demanded in 9 source files and checked by nothing; nothing
  detects that context read earlier has drifted; and source edits route to a skill only 38% of
  the time. One failure class, five fixes.

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
  2. The routing hook's skill block is generated from skill frontmatter, so the hook and the
     rule can no longer disagree.
  3. `sync.sh` run from a tree older than the recorded install refuses and names the gap.
  4. A turn that edits source and emits no `ponytail self-pass:` line is refused, and a mere
     quotation of that line inside prose or a fence does not satisfy it.
  5. A continuation turn that edits source without routing is caught, not just the first edit
     of a fresh turn.
  6. Per-file drift is reported against an explicit baseline, with unreachable commits and
     dirty worktrees distinguished from clean.
  7. Provenance labels exist as a rule, and `[UNVERIFIED]` cannot back an `[ERROR]` finding or
     a code edit.
  8. `bash check.sh` exits 0, `bash sync.sh` prints `Sync complete.`, and a second consecutive
     run reports `(up to date)` everywhere.

- **In scope:**
  - **F0 (done)** `hooks/craftkit-transcript.js:isUserTurn` treats an injected entry
    (`isMeta === true`) as not a turn boundary, covering both a skill body and stop-hook
    feedback. Fixtures in `check.sh` model the injected entry, which they previously did not.
  - **F1 (reduced)** Generate the routing hook's skill block from each skill's existing `name`
    and `description` frontmatter into a managed region, plus a currency check. This closes the
    drift bug `CLAUDE.md` documents ("the hook text duplicates the routing table, update
    both"). Nothing else from the original F1 survives; see Out of scope.
  - **F2** `rules/grounding.md`: the three provenance labels
    (`[verified: <cmd|file:line>]`, `[from context.md @<sha>]`, `[UNVERIFIED]`) and the law that
    `[UNVERIFIED]` may not back an `[ERROR]` finding or a code edit.
  - **F2** Drift detector using `git diff --name-only <baseline> -- <paths>`, one command for
    all paths, which honors clean filters, covers staged and worktree states, and detects
    renames. Distinguishes clean, drifted, and cannot-verify, where an unreachable baseline
    (squash merge, rebase, amend, gc) reports cannot-verify rather than clean.
  - **F2** `hooks/gate-stale-context.js` (PreToolUse on Edit), firing only for files the
    current action touches.
  - **F2** Cold agents review only content handed to them, via `craftkitInject: grounding`
    rather than hand-copied rule text.
  - **F3** `sync.sh` records the installed version in `~/.craftkit-state/` and refuses a
    downgrade, naming both versions.
  - **F4** `hooks/gate-verify-on-stop.js` also refuses a turn that edited source and carried no
    `ponytail self-pass:` line, line-anchored and fence-stripped so a quotation does not pass,
    with both refusal reasons collected before returning so one turn yields one message.
  - **F4** Per-file added-comment vs added-code counts in that refusal message, against an
    explicit diff baseline so pre-existing dirt is not attributed to this turn.
  - **F5** Extend `hooks/gate-skill-first.js` to cover the continuation case: a turn that edits
    source with no routing carrier is the measured miss population, and the gate currently asks
    once per turn only.

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
    the original covers", so it holds the count where F4 wants it cut; its patterns target
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
  5. **One command, not two per file.** `git diff --name-only <baseline> -- <paths>` replaces
     `hash-object` plus `rev-parse`, and handles filters, staging, and renames for free.
  6. **Derive, don't record.** The model-tier hook is the in-repo proof: hardcoded ids went
     stale, derived ids cannot.

- **Risks & open questions:**
  - *F5 is the one unproven lever.* Enforcement moved routing from 21% to 51%, but the
    remaining misses include legitimate no-skill work (branch syncs, conflict resolution). A
    gate that fires on those trains click-through, the failure this repo has already documented.
    Needs a precision bound before it ships.
  - *T-1's miss classification is judgment, not mechanics.* ~15 of 25 flagged turns are genuine
    misses; 5 are task notifications and ~5 are git plumbing.
  - *Two months and 74 source-editing turns is a small sample.* The direction is clear, the
    magnitude is not.
  - *`isMeta` is undocumented.* If it disappears, both gates revert to a truncated turn. Marked
    `ponytail:` and pinned by fixtures.
  - *F4 adds a second refusal to every code turn,* which must read as one message.
  - *Open:* should the comment ratio ever gate above some bound, or only inform.
  - *Open:* should `flag self-pass:` get the same treatment in a follow-up.
  - *Open:* what precision bound makes F5 shippable.

- **Acceptance:**
  - [x] Given a transcript where a `Skill` tool_use is followed by an `isMeta` skill body and
        then an `Edit`, both gates pass; with the `Skill` call removed, the skill gate still
        asks; with `isMeta` stripped, the new checks fail.
  - [ ] Given a skill's `description` edited without regenerating, `check.sh` fails reporting
        the hook block stale; regenerating twice yields no diff.
  - [ ] Given an install recorded newer than the tree being synced from, `sync.sh` refuses and
        names both versions; equal or newer proceeds; a first run with no recorded version
        proceeds and records one.
  - [ ] Given a turn that edited source with no `ponytail self-pass:` line, the stop gate
        refuses, naming the line and the per-file comment-to-code counts.
  - [ ] Given a turn whose only occurrence of that line is inside a fence or mid-sentence, or
        which edited a rule file containing the line, the gate still refuses.
  - [ ] Given a turn with the line present as its own claim, it passes on either form; given a
        turn that edited no source, it passes untouched.
  - [ ] Given both refusals due at once, the turn is blocked once with both named.
  - [ ] Given a continuation turn that edits source with no routing carrier, the skill gate
        asks; given one that routed earlier in the same turn, it does not.
  - [ ] Given a baseline commit and one file edited since, the detector names that file; with
        none edited it reports clean; with an unreachable baseline or outside a git repo it
        reports cannot-verify, never clean.
  - [ ] Given a file renamed since the baseline, the detector reports it without fataling.
  - [ ] Given an Edit to a drifted file, `gate-stale-context.js` asks; to an undrifted file it
        passes silently; on malformed stdin it exits 0.
  - [ ] Given `rules/grounding.md` added, README carries its row, `check.sh` covers it, and the
        12 `agents/*.md` carry the injected body after sync.
  - [ ] `bash check.sh` exits 0; `bash sync.sh` prints `Sync complete.`; a second consecutive
        `sync.sh` reports `(up to date)` everywhere.

### Task Plan
**Updated:** 2026-09-11T08:36:45Z · **By:** /plan

| ID | Task | Acceptance | Depends on | Executes via |
|----|------|-----------|-----------|--------------|
| T0 | **DONE** `isUserTurn` ignores injected (`isMeta`) entries so a skill body no longer truncates the turn | 5 `check.sh` assertions pass; all 3 positive ones fail with the fix removed | none | `/fix` (done) |
| T1 | Generate the routing hook's skill block from each skill's `name` and `description` into a managed region, plus a currency check | Editing a description without regenerating fails `check.sh`; regenerating twice yields no diff | none | `/build` |
| T2 | `rules/grounding.md`: three provenance labels and the `[UNVERIFIED]` law, plus README row and a `check.sh` check | README row present; `check.sh` covers it; installs to all 4 tools; second sync a no-op | none | `/build` |
| T3 | Drift detector on `git diff --name-only <baseline> -- <paths>`, distinguishing clean, drifted, cannot-verify (unreachable baseline, non-git, renames) | Behavioral `check.sh`: edited named, unedited clean, unreachable baseline and non-git both cannot-verify, rename reported without fatal | none | `/build` |
| T4 | `hooks/gate-stale-context.js` (PreToolUse on Edit), scoped to files the action touches, registered in `_CRAFTKIT_HOOKS` with its README row | Drifted asks; undrifted silent; malformed stdin exits 0; hook-table check green | T3 | `/build` |
| T5 | Point the three `*-context` skills and Standard context loading at the detector, recording an explicit baseline in the doc header | A regenerated doc carries a baseline the detector accepts; the freshness step consults it | T3 | `/build` |
| T6 | Opt the 12 `agents/*.md` into `craftkitInject: grounding` so cold agents carry the live rule instead of a copy | `craftkitInject` sources resolve; installed agents carry the body; second sync a no-op | T2 | `/build` |
| T7 | `sync.sh` version guard: record the installed version in `~/.craftkit-state/`, refuse a downgrade naming both versions | Behavioral `check.sh`: older-over-newer refuses; equal or newer proceeds; first run records | none | `/fix` |
| T8 | Extend `gate-verify-on-stop.js` with the self-pass refusal, line-anchored and fence-stripped, collecting both reasons before returning | Undeclared refused; quoted or fenced mention still refused; declared passes; no-source-edit untouched; both reasons in one message | none | `/fix` |
| T9 | Add per-file added-comment vs added-code counts to that message, against an explicit diff baseline | Counts shown per changed file; pre-existing dirt not attributed to the turn; counting never triggers the refusal | T8 | `/build` |
| T10 | `check.sh` fixtures for T8: declared, undeclared, fenced mention, edits-a-rule-file, no-source-edit, shell-route, delegated, malformed stdin, both-refusals, negative control | Removing the T8 check makes every undeclared fixture fail; malformed stdin exits 0 | T8 | `/fe-test` |
| T11 | Extend `gate-skill-first.js` to the continuation case, with a precision bound that spares legitimate no-skill work (branch sync, conflict resolution) | Behavioral `check.sh`: continuation source edit with no carrier asks; a turn that routed earlier does not; a git-plumbing turn does not | none | `/fix` |
| T12 | Release: version bump in `package.json` and the README header, plus a matching `CHANGELOG.md` section | `check.sh` version-consistency check green; `sync.sh` clean and idempotent | T1-T11 | `/parallel-ship` |

**Parallelizable now:** T1, T2, T3, T7, T8, T11
**Critical path:** T3 → T4 → T12, and T8 → T9 → T12 (3 deep)

**Sequencing note:** T8 lands early despite having no dependents. It makes every later task's
own self-pass enforceable, so building the rest first means building it under the advisory
regime this change exists to end.

**T11 is the one task without evidence behind its design.** Its lever is proven (enforcement
moved routing from 20.7% to 51.1%), its precision bound is not. Build it last of the
parallelizable set, or split the bound into its own measurement pass first.

### Decisions
_(appended by /adr)_
<!-- END PLANNING -->
