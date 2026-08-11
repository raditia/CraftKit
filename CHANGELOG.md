# Changelog

Every notable change to craftkit, newest first. Each entry is what the release actually
changed and why it was needed — the reasoning is kept because most of these fixes exist to
stop a bug that had already shipped and gone unnoticed.

Versions are cut by `.github/workflows/release.yml` on push to `main`: it reads the version
from the README header and this file's matching `## <version>` section for the release notes.

## v1.26.0 — 2026-08-11

Split the changelog out of the README and gave it a readable shape.

The README was 88K, and **41.9K of it — 48% — was the changelog: 40 table rows**, the largest a single 6,025-character cell. Splitting the file was the obvious half; the real problem was that changelog prose was living in table cells, where a 3K entry is a wall no matter which file holds it. So this does both.

- **`CHANGELOG.md` created**, one `## vX.Y.Z — date` section per release, newest first. All 40 entries moved with bodies preserved verbatim (verified byte-for-byte before reformatting). README: **88K → 44.5K, 775 lines.**
- **The seven oversized entries reformatted** into a one-line summary plus bullets — `v1.19.0` (6.0K, its inline `(1)`–`(4)` / `(a)`–`(d)` enumerations became real bullets), `v1.22.0`, `v1.23.0`, and this session's `v1.24.0`, `v1.24.1`, `v1.25.0`, `v1.25.1`. No prose block over 1.9K remains.
- **The release workflow's silent failure mode is gone.** `release.yml` extracted notes with `grep "| \`$VERSION\`" README.md` and, on no match, fell back to `ENTRY="See README for full changelog."` — so moving the changelog would have shipped generic notes on every future release with no error at all. It now extracts the section between `## <version>` headings in `CHANGELOG.md` and **fails the release** when the section is missing.
- **The trailing space in `"^## " v " "` is load-bearing.** Without it, `awk` matches `v0.2.1` against `v0.2.10` and concatenates both entries into the notes. Verified synthetically by appending a `v0.2.1`/`v0.2.10` pair: the guarded match returns one entry, the unguarded one returns both.
- **`check.sh` check 10** now reads the newest `## vX.Y.Z` section of `CHANGELOG.md` instead of the README's top table row, so `package.json` + README header + `CHANGELOG.md` must still agree.
- **Deliberately not split further.** After this the README is 775 lines — normal. `Using the workflows` (15.6K) is linear teaching content that loses its single-scroll narrative if broken up, and the Skills/Agents reference tables are check 9's grep targets, so moving them costs a check rewrite for readers who reach them by table-of-contents anyway.
- **Stale references from `v1.24.0` swept up in `CLAUDE.md`:** `sync.sh` described as distributing into "all 6 tools", and the never-edit-installed-files warning still naming VS Code settings instead of `~/GEMINI.md` and `~/.codex/`. The check-list summaries in both `CLAUDE.md` and README now name checks 13–15, which had been added without updating either.

## v1.25.1 — 2026-08-11

Paid the `v1.24.0` ponytail debt — the Copilot and Crush adapters are gone.

They were kept solely so an existing install could uninstall itself. That pass has run, so this deletes exactly the list the `ponytail:` marker named: `adapters/copilot.sh`, `adapters/crush.sh`, their `source` lines, `RETIRED_ADAPTERS`, `retire_adapter`, `retire_copilot_projects`. **−281 lines**, no behavior change for anyone already on ≥ v1.24.0, and the repo now carries **no `ponytail:` markers at all**.

- **Stated plainly, because it is why the code existed:** a machine that never pulled v1.24.0–v1.25.0 will never be cleaned up, and keeps stale Copilot entries in VS Code `settings.json` plus a frozen Crush managed block. Recover with `git show a8b0bec:adapters/copilot.sh`.
- **`check.sh` check 13 rewritten around the invariant that outlives retirement.** Its `RETIRED_ADAPTERS` half became unreachable once the array was deleted. Rather than dropping that half, it now asserts the reverse direction: every `adapters/*.sh` on disk must appear in `ADAPTERS` — precisely the half-finished state this release cleaned up, an adapter file left behind reading as a supported tool while nothing syncs it. The gate now fails both ways (listed-but-missing, present-but-unlisted); both verified failing before passing, the orphan case by restoring `crush.sh` from `a8b0bec`.
- **`CLAUDE.md` retirement section rewritten** from a description of live code into the two-release *procedure* to follow next time: teardown pass first, keep the adapter sourced under `RETIRED_ADAPTERS`, mark it `ponytail:` with the release it dies in, delete one release later, never touch files the adapter wrote into other repos. The mechanism is worth keeping as institutional knowledge even though the implementation is gone.

## v1.25.0 — 2026-08-11

The routing gate demanded a `parallel-*` command from contexts that structurally cannot run one.

A `parallel-*` orchestrator exists to spawn agents, so a subagent (which gets no Agent tool) or a session whose instructions disable spawning cannot execute one. Yet `rules/using-agent-skills.md` declared *"Dynamic parallel is the default"* unconditionally, and core behavior #10 made announcing the matched skill a `MANDATORY GATE` with `Never silently skip`. Nothing in the always-active rule or the routing hook acknowledged a no-spawn context.

The `Sequential fallback` section held the exact commands needed but framed them only as *"when you want a lightweight, single-pass run"* — a preference, never a sanctioned substitute. That left such a context two options, and it took the honest one: narrate the conflict every turn (*"normally /parallel-build, but this session forbids subagent spawning, so I run … inline"*), which is core behavior #9 working as designed and a per-turn token cost the user pays. Same defect class as the two `v1.19.0` fixed — an always-active rule stating something unconditionally that is false in some contexts.

- **Fixed by naming the substitution** instead of leaving it to be re-derived: a no-spawn table (`/parallel-build`→`/build`, `/parallel-review`→`/review`, `/parallel-ship`→`/ship`, `/team-build`→`/build`) in the rule, and one line in `hooks/craftkit-routing.js`.
- **Announce the command actually run**, state the substitution *once* if it costs a validation axis, then stop repeating it — explicitly distinguished from the `[WARNING] agent skipped` case, which is an agent that spawned and died.
- **The old fallback table survives**, retitled *"Sequential fallback by choice"*: preferring sequential when spawning **is** available remains a separate, valid reason.
- **No new commands** — all four twins already existed, which is why the fix is a mapping rather than content.
- **`check.sh` check 15**: every `commands/parallel-*.md` must have a real sequential twin on disk and be mapped in both the rule and the hook, since those two duplicate the routing table by design and drift silently. All three failure branches verified failing before passing (missing twin file, mapping absent from rule, mapping absent from hook).
- **Two bugs in the check itself, caught by that verification:** `$_pn\`` and `$_pn→` both absorb the following bytes into the variable name under `set -u`, so the check died with `unbound variable` instead of reporting. Braces now delimit every expansion.

## v1.24.1 — 2026-08-11

The routing hook's node path was pinned to a version fnm can prune, and the wire that set it was write-once.

Hooks spawn with no shell profile and a stripped `PATH` (`/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.`), so the registered command must carry an absolute interpreter. Three layers all produced the same silent degradation `v1.23.0` fixed for the `rtk` `PreToolUse` hook: a dead `UserPromptSubmit` hook simply yields no `additionalContext`, so the entire skill-first routing gate disappears with nothing but a dim hook error to show for it.

- **1 — the path was version-pinned.** `_resolve_node_bin` preferred `~/.local/share/fnm/node-versions/<v>/installation/bin/node`. Absolute, but one `fnm uninstall` of that version turns the hook into `node: command not found`. It now prefers a package-manager-managed symlink (`/opt/homebrew/bin/node`, then `/usr/local/bin/node`) that brew repoints on upgrade, falling back to fnm only when no managed node exists.
- **2 — the wire was write-once.** `_craftkit_hook_wire_settings` bailed with `sys.exit(0)  # already registered` on any existing entry, freezing the interpreter at whatever install day resolved — the same orphan class as an adapter dropped from `ADAPTERS` with no teardown, meaning no fix could reach an existing machine. It now re-points an entry whose interpreter no longer exists, or is a version-pinned fnm path, printing the before/after, and leaves a working non-pinned command alone since that may be deliberate.
- **3 — found only because the fix was tested against a live install and changed nothing.** `install_claude_craftkit_hook` called the wire *inside* the branch that copies a changed hook script, so on any machine whose `craftkit-routing.js` was already current — every machine that had synced once — the wire never ran. Now called unconditionally, printing only when it re-points, so a repeat sync stays silent.
- **`check.sh` check 14**: `_resolve_node_bin` must return an absolute, non-version-pinned path whenever a managed node is present (skipped otherwise). Verified failing with the preference removed before being made to pass.
- **Verified on a live install:** run 1 printed the re-point from `fnm/node-versions/v22.22.3` to `/opt/homebrew/bin/node`, run 2 reported no work, and the re-pointed command exits 0 under `env -i PATH=/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.`.
- Found while diagnosing a `node: command not found` error that turned out to be the caveman plugin's own `plugin.json` declaring bare `node`; craftkit's hook was already absolute, but the investigation surfaced that it was one pruned fnm version away from the identical failure.

## v1.24.0 — 2026-08-11

Narrowed the fan-out from six tools to four — GitHub Copilot and Crush retired.

The kept set (Claude Code, Cursor, Gemini CLI, Codex CLI) is the set where every member has a headless entry point (`claude -p`, `cursor-agent`, `gemini -p`, `codex exec`), which is the prerequisite for one tool spawning work in another. Copilot is IDE-bound and Crush is TUI-only, so neither could ever participate in cross-tool agent fan-out.

- **Retirement is a teardown pass, not a deletion.** Dropping an adapter from `ADAPTERS` alone is the harmful move: the removal loop that would uninstall it stops running, so the tool keeps loading a frozen copy of the rules indefinitely with nothing to signal why.
- **`RETIRED_ADAPTERS` + `retire_adapter`** keep the adapter *sourced* and replay its own `uninstall_<a>_{skill,rule,command,agent}` over every name in its state files, call `finalize_<a>`, then delete the state files so the pass is a permanent no-op. Reusing each adapter's own teardown instead of re-deriving paths is the point — Copilot's removal edits the user's VS Code `settings.json` through `jq`, Crush's strips a managed block out of `CRUSH.md`. Both adapter files are marked `ponytail:` for deletion one release out.
- **Deliberately not cleaned up:** per-project Copilot `@`-agents wrote real files into *other* repos, quite possibly committed there, so `retire_copilot_projects` prints and unregisters the `.github/agents` paths rather than deleting inside someone else's git repo. `scripts/init-copilot-agents.sh` deleted — teardown never calls it.
- **`check.sh` check 13 — adapter arrays resolve.** `sync.sh` calls adapter functions by string interpolation, so a name listed with no sourced file dies at the first call, *mid-sync*, after some tools are already written. Asserts every name in either array has both an `adapters/<a>.sh` and a source line, and that no name sits in both. Verified failing before passing.
- **Codex CLI promoted to a first-class row.** Narrowing exposed that Codex was a sync target with no entry in the model-routing table while the retired Copilot had one. It now carries its tier row and `codex exec` shell fan-out; `/ideate`'s portability table moves it from degraded to full parallel spawn.
- Tool lists reconciled across `README.md`, `CLAUDE.md`, `package.json`, `commands/{pr-message,team-build}.md`, `skills/{docs,ideate}/SKILL.md`. Historical changelog entries left as written — they record what was true at the time.

## v1.23.0 — 2026-08-10

**RTK's `PreToolUse` hook was silently dead, and with it the whole token filter.**

`ensure_tools` calls `rtk init -g --auto-patch`, which registers the hook as bare `rtk hook claude`. Claude Code spawns hooks under a stripped `PATH` — `/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.`, no `/opt/homebrew/bin`, no fnm — so the bare name died with `/bin/sh: rtk: command not found`. The failure is *non-blocking*, which is what made it expensive rather than obvious: the tool call proceeded unrewritten, so `git status` never became `rtk git status` and every Bash call ran unfiltered, with nothing but a dim hook error to show for it. Against the 72.8% / 35.0M tokens `rtk gain` reports saved, that is the entire point of the proxy silently switched off.

- **`_rtk_hook_absolutize()`** in `sync.sh` rewrites any bare `rtk hook` `PreToolUse` command to the absolute path from `command -v rtk`, called right after each `rtk init` — necessary because `rtk init` re-registers the bare form on every run, so a one-time hand fix would not survive the next `AGENTIC_SETUP=1` sync. Resolved dynamically rather than hardcoded, so Intel Macs (`/usr/local/bin`) and Linux work too.
- Same class the Claude adapter already solved for node via `_resolve_node_bin`; the rtk hook was the unpatched sibling. (`v1.24.1` later found that `_resolve_node_bin` was itself pinned to a prunable fnm version.)
- **`check.sh` check 12** asserts `ensure_tools` both defines and calls `_rtk_hook_absolutize`, guarding the fix from deletion; verified failing before passing.
- **Verified end-to-end under `env -i`**, the exact environment that broke it: the hook now returns its `RTK auto-rewrite` payload.
- **Not fixed and not ours** — the companion `node: command not found` comes from the caveman plugin's own `plugin.json` declaring bare `node "${CLAUDE_PLUGIN_ROOT}/..."`; the plugin cache is overwritten on update, so that needs an upstream PR. Harmless meanwhile because the installer left absolute-path duplicates of both caveman hooks in `settings.json`, which is why caveman works while the error prints.

## v1.22.0 — 2026-08-09

Three skills adopted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) after a duplicate/conflict audit against the existing catalog.

- **`/grill`** — interactive stress-test of an existing plan/decision via frontier-round interview (design tree; whole frontier asked per round, each question with a recommended answer; sub-agents fetch facts so the user only makes decisions). Captures resolved terms into a standalone `docs/glossary.md` — deliberately not `docs/context.md`, which `/fe-context` regenerates — and offers `/adr` on the three-condition test. Positioned against `/interview` (de-fuzz a new ask, one question at a time) and `plan-roaster` (cold single-pass) so all three keep distinct niches.
- **`/research`** — background agent investigates primary sources only (official docs, source code, specs) and writes a cited note into the repo.
- **`/handoff`** — compacts the session into a handoff doc (goal, verified state, decisions with their why, ordered next steps, suggested skills) in the OS temp dir, referencing existing artifacts by path instead of duplicating them, secrets redacted.
- **`/interview` upgraded** with two grilling ideas: mark the recommended answer among candidates, and "facts are your job, decisions are the user's" — look up what the environment can answer before spending a question.
- **Spec-conformance flag condition** in the parallel classifier: when `docs/context.md` has a PLANNING block, `code-quality` is instructed to verify the diff against the planned spec and acceptance criteria, closing the `/define` → build → review loop.
- **`CLAUDE.md` gains "Writing levers for agent-consumed docs"** (no-op test, leading words, state-the-positive, pointer wording as invocation lever, completion-criteria demand) mined from `writing-for-agents`.
- **Caveman dedup** — a token audit of the live install found the caveman instructions loaded ~4×: `rules/caveman.md` synced into the managed block, a second copy in an orphaned `AGENTIC-GENERAL` block left by an old installer, a stray third copy, plus the caveman plugin injecting the same text per-turn via its hooks. One channel wins: the plugin (level tracking, stats, persistence). `rules/caveman.md` deleted — the sync state-file removal loop uninstalls it from all six tools automatically — and `using-agent-skills` / README now name the plugin as the sole delivery. **~1.2k tokens/session + ~150 tokens/turn reclaimed.**

**Considered and skipped as duplicates or conflicts:** `diagnosing-bugs` (`/debug`), `tdd` (test-skill routing), `code-review` (`/parallel-review`; its Spec axis adopted as the flag condition above), `to-spec`/`to-tickets`/`triage`/`wayfinder` (tracker-centric; `/spec` + `/plan` cover the need), `ask-matt` (routing hook), `improve-codebase-architecture`/`codebase-design` (deepening philosophy clashes with ponytail's deletion bias).

Routing wired: hook `General:` line, discovery-tree entries (grill under Planning & docs, new General-utilities group), grill tiebreaker.

## v1.21.0 — 2026-08-06

**Platform detection moved from inference to `cwd`.** The routing hook told the model to detect RN/web vs Android vs iOS itself, and `using-agent-skills` warned that announcing a `/fe-*` skill on a `.kt` or `.swift` task is a routing error — a rule against a mistake the setup invited, since the model only had filenames to go on and a native repo with no staged changes gives it nothing. That is deterministic work handed to a probabilistic step, against core behavior #7 (if code can answer, code answers). `hooks/craftkit-routing.js` now walks up from the hook payload's `cwd` (falling back to `process.cwd()`, capped at 12 levels) checking each level for `settings.gradle{,.kts}` / `build.gradle{,.kts}` → Android (MVP), `Podfile` / `Package.swift` / `*.xcodeproj` / `*.xcworkspace` → iOS (MVVM-C), `package.json` → React Native / web (EVPMR). Nearest ancestor wins, so an RN root reports RN while its `android/` subdir reports Android — the right answer in both places; several markers at one level report as mixed; no marker anywhere emits no line rather than a guess. The result is injected as an authoritative `Platform (detected from cwd)` line, so `"write tests for this"` in an Android repo can no longer land on `/fe-test`. **New `check.sh` check #11, behavioral not grep** — it builds three fixture dirs, runs the real hook against each, and asserts the label, plus asserts the hook exits 0 on malformed stdin. Both matter because a `UserPromptSubmit` hook that dies just yields no context: a marker typo or a parse crash removes the entire skill-first gate silently, and a grep-based check would pass on detection that never fires. Skips with a notice when `node` is off `PATH`. Verified to fail before being made to pass, for both classes.

## v1.20.0 — 2026-08-06

**Barrel-import discipline moved to write time.** The guidance existed — `skills/fe-performance/SKILL.md` had a "Direct imports, not barrels" block — but it lived in an on-demand *performance* skill, so it was absent from context during ordinary feature and bugfix work. That is exactly when the mistake gets made: a shared helper was added to a package barrel and imported through it from three call sites, and the cost only surfaced in PR review. The barrel re-exported hooks, a query provider and a context alongside pure utils, so two of those importers pulled react-query, feature-control and provider code into their module graph for one string function. New **`## Imports`** section in `rules/fe-rules.md` (always active), covering the module-over-barrel rule with a monorepo example, the corollary that a new shared helper must **not** be added to the barrel (an available path invites the costly import next time), consistency when the file already imports from that barrel, and the test bonus — a deep-imported helper survives a `jest.mock` of the barrel with no `jest.requireActual` threading. Per the token audit, the `fe-performance` block collapses to a one-line pointer plus its own distinct job (audit existing barrel imports during a bundle-size investigation), so the concept has one home. Reaches the `fe-review` cold agent live via its existing `craftkitInject: fe-rules` — no hand-copied duplicate.

## v1.19.0 — 2026-08-05

**The parallel workflows now run on iOS and Android, not just RN/web.** `/parallel-review`, `/parallel-ship`, and `/parallel-build` hardcoded `rtk tsc` + jest-93% gates and a `fe-*`-only agent set, and the classifier keyed on `View*.tsx`/`Presenter*.ts` — so a `.kt` or `.swift` branch landed in a command with the wrong gates and no matching reviewer, while the sequential `/build` `/fix` `/ship` had platform-routed for versions. Closed in four parts.
- **(1)** **`craftkitInject` resolves skills, not just rules** — `adapters/claude.sh` now looks up each injected name as `rules/<n>.md` first, then `skills/<n>/SKILL.md` (`_claude_inject_source_path`), so a cold agent can carry a live *skill checklist*. That is what makes native agents maintainable: no hand-copied duplicate to rot.
- **(2)** **Six native cold agents** — `android-review` `android-a11y` `android-performance` `ios-review` `ios-a11y` `ios-performance`, each a thin prompt over its injected skill, each told it cannot run Gradle/Bazel/SwiftLint/TalkBack/VoiceOver/Instruments and to name the manual check or measurement still owed instead of asserting one. `code-quality`, `ponytail-review`, and `adversarial` stay platform-agnostic and run on all three.
- **(3)** **Platform-aware classifier** — `using-agent-skills` gained Step 1.5 (detect platform; a mixed diff unions both tables) and per-platform Step 2 tables for MVP (Activity/Fragment/Widget, Presenter, ViewModel, Repository, Dagger, `strings.xml`) and MVVM-C (ViewController/View/Cell, ViewModel, Fetcher, Contract/Factory/Coordinator, `*.strings`); the adversarial trigger now counts layers in any of the three architectures, and Step 4 announces the detected platform.
- **(4)** **Step 0 in all three commands** — per-platform gate rows (`gradlew lintGeneralDebug` + `testGeneralDebugUnitTest`; `swiftlint lint` + `bazelisk test`), the 93% coverage bar scoped to RN/web with native reporting actual module coverage or stating it isn't measured, native context downgraded to sibling-screen reading for single screens, and the repeated per-agent payload blocks collapsed into one message template + an agent/platform/include-when table (which is what kept 12 agent variants from tripling these files). `parallel-build` also routes its scaffold/patterns/test phases per platform; native has no `*-patterns` agent by design — the patterns skill already ran in Phase 2 and the review agent covers the layer contract.

**Two pre-existing routing bugs found by the follow-up repo audit and fixed in the same release.**
- **(a)** *Test intent was platform-blind* — the routing table sent every "write tests" / "coverage is low" phrasing, plus both ambiguous-test tiebreakers, to `/fe-test`, which is Jest + 93% + EVPMR paths; on a `.kt`/`.swift` repo that is the wrong skill while `/android-test` and `/ios-test` sat unreachable unless named. The row and tiebreakers now resolve platform first, `skills/fe-test/SKILL.md` opens with a platform gate that stops and redirects (and forbids carrying the 93% bar into native), and the hook + README rows match.
- **(b)** *`docs/context.md` was declared mandatory with no exceptions* while ten `{android,ios}-*` skills declared they don't use it — a direct contradiction inside an always-active rule. Standard context loading now states its scope up front (RN/web, plus native multi-screen only), names the sibling-screen baseline as correct for native single-screen work, generalizes project-root detection to `settings.gradle` / `*.xcodeproj`, and picks the generator per platform (`/fe-context` · `/android-context` · `/ios-context`); failure-mode #9 no longer reads as absolute.
- **(c)** *`skills/pr-message/` deleted* — a 7-line stub whose body only pointed at `commands/pr-message.md`. Because a skill with `alwaysApply: false` installs to the same dest a command does (`adapters/claude.sh:4-5`), the two passes wrote the same file every sync on all six tools; the 137-line command won only because the commands pass happens to run second. Ordering luck, not design. Removing the stub makes the sync idempotent for the first time — `commands: (up to date)` everywhere instead of a perpetual `+ installing: pr-message`. The state-file removal loop uninstalled the orphan automatically; nothing referenced the stub.
- **(d)** *Cursor re-wrote all four rules on every sync* — `install_cursor_rule` injects `alwaysApply: true` after the opening `---`, but `sync_rules_adapter` diffed the **raw source** against the **transformed dest**, so every rule compared as changed forever. Same bug class the agents pass already solved: `sync_rules_adapter` now honours an optional `effective_<adapter>_rule_source` hook (mirroring `effective_<adapter>_agent_source`, including the never-delete-the-source temp guard), and `adapters/cursor.sh` declares one over a shared `_cursor_render_rule` so install and comparison can't drift. Cursor was the only adapter transforming rules on install — the other five plain-`cp` to a staging path, so their raw diff was already honest. `sync.sh` is now idempotent end to end: a second run reports no work on any of the six tools.

**Added `check.sh` — the repo's first verification step.** All four bugs above were mechanical and grep-findable, and all four survived because nothing greps: with no build, lint, or test suite, "verification" was `sync.sh` printing `Sync complete.`, which only proves files copied. `check.sh` codifies core behavior #7 (if code can answer, code answers) with ten checks, each one a regression guard for a bug that actually shipped — `subagent_type` resolution, skill/command dest collision, flat `skills/`, frontmatter/path name agreement, `craftkitInject` resolution, routing-hook targets, per-platform orchestrator coverage, absolute `docs/context.md` claims, README coverage of every agent and skill, and version agreement across `package.json`/README header/changelog. Each was verified to fail before being made to pass. Wired into `CLAUDE.md` and the README as a pre-commit gate.

## v1.18.0 — 2026-08-05

**Comment bloat is now a scored rubric tag.** `v1.17.0` gave the writing side a comment-discipline block, but the ponytail rubric had no tag for it — so neither the write-time self-pass nor `/ponytail-review` ever scored comments, and only `agents/code-quality.md` (readability axis) caught them. Added a sixth tag **`narrate:`** to the rubric in `rules/karpathy-guidelines.md` rule 2 — fails on a comment that restates the code, or on comments denser than the file around it. One row propagates to every consumer: the write-time self-pass, `/ponytail-review`, `/ponytail-audit`, `/android-review`, `/ios-review`, all three scaffolds' after-generating checklists, and the `ponytail-review` agent (live via `craftkitInject`). Tag-specific protected list added so the guard can't strip what matters: a comment carrying a non-obvious *why*, license/pragma headers, and doc comments on public APIs. The comment-discipline block now closes on the causal point — excessive comments mean the code isn't expressive enough, so fix the code — and names `narrate:` as its enforcement. Overlaps `code-quality`'s comment-noise check only on the same `file:line` (→ `[CONSENSUS]` in synthesis, same precedent as the `delete:`/dead-code overlap).

## v1.17.0 — 2026-08-04

**Ponytail moved to write time — kills the review-rewrite loop.** Ponytail lived only on the review side: writers got the abstract ladder, reviewers scored by a five-tag rubric they never saw, so `/ponytail-review` always found a pile and applying it churned files. Fixed in three places. (1) **Shared rubric** — the five tags (`delete:` `stdlib:` `native:` `yagni:` `shrink:`) and the protected list moved into `rules/karpathy-guidelines.md` rule 2 (always active); the three hand-maintained copies in `skills/ponytail-review`, `skills/ponytail-audit`, and `agents/ponytail-review` now reference it (the agent already receives it live via `craftkitInject`). One list, both sides. (2) **Write-time self-pass** — any turn that writes code scans its own diff against the rubric before reporting done, cutting each hit or marking it `ponytail:` with its ceiling, and reports `ponytail self-pass: clean` / what was cut. Wired as an explicit gate in `/build` Step 3, `/parallel-build` Phase 2 (+ report line), `/team-build` per-task definition of done, the after-generating checklists of **all three** scaffolds (`/fe-scaffold`, `/android-scaffold`, `/ios-scaffold`), and CI-gate #3 in `using-agent-skills` core behavior #6. `/android-review` and `/ios-review` gained an **Over-engineering** section with platform-specific hits (Android: forwarding UseCase, single-subclass `sealed class`, hand-rolled `map`/`associateBy`; iOS: single-conformer protocol, forwarding Fetcher wrapper, hand-rolled `compactMap`/`first(where:)`/`Result`, unread Dependency field). The `ponytail-review` agent is now the backstop, not the first pass. (3) **Apply = deletion, never rewrite** — findings act on the named `file:line` only (remove, or swap in the named stdlib/native call); no restructuring, renaming, or tidying while in there, and a rewrite-shaped finding is stated and left alone. The agent must also emit only deletion-actionable findings.

## v1.16.1 — 2026-08-03

**Detached Jumbo.** Removed the `jumbo-cli` global-install block from `sync.sh` `ensure_tools` and its Tooling-table row. Jumbo is a *per-project* memory CLI (`.jumbo/`), but CraftKit never initialized one — it rode along as a global install with zero effect inside this repo, whose memory/context is already handled by `docs/context.md` + the routing/skills system. No behavior change here; existing global `jumbo` binaries are left untouched (uninstall manually with `npm rm -g jumbo-cli` if unused elsewhere).

## v1.16.0 — 2026-08-03

**Automatic over-engineering guard + cheapest-tier reconcile.** New cold agent **`ponytail-review`** (`agents/ponytail-review.md`, `craftkitInject: karpathy-guidelines`, `model: sonnet`) — spawned by `/parallel-build` (Phase 5) and `/parallel-ship` (Phase 2) whenever non-test, non-resource source changes, so bloat (reinvented stdlib, speculative abstraction, dead flexibility) gets caught without a manual `/ponytail-review`. `/fix` gained an inline bloat check on the fix diff. Overlaps `code-quality` only on dead-code (→ `[CONSENSUS]` in synthesis, not waste); `parallel-review` deliberately excluded. Injection (not invocation) is how the discipline reaches cold agents — write-time reach for any future cold *writing* agent is the same `craftkitInject` hook. Also reconciled the plan-blind `cheapest — claude-haiku-4-5` label across 13 skills: the **Model routing** table gains a **Cheapest** column (personal `claude-haiku-4-5` / enterprise `claude-sonnet-5`), skills now reference the table instead of hardcoding haiku, and `hooks/craftkit-routing.js` injects the detected `cheapest=` alongside everyday/escalate. Enterprise floor is `claude-sonnet-5`, matching the sonnet pin on all cold agents (static frontmatter can't branch on plan).

## v1.15.0 — 2026-07-25

**Plan-aware model routing for Claude Code.** `hooks/craftkit-routing.js` now reads `~/.claude.json` → `oauthAccount` on every prompt and detects account tier: Gmail-domain login → personal (everyday `claude-sonnet-5`, escalate `claude-opus-4-8`), `organizationType` containing "enterprise" → enterprise (everyday `claude-opus-4-8`, escalate `claude-fable-5`), anything unreadable/unrecognized → personal (safe default). Detected tier is injected as `additionalContext` each turn. `rules/using-agent-skills.md` **Model routing** table gains a Plan column and generalizes the escalation/fusion-panel process prose to reference "the tier's Escalate model" instead of a hardcoded `claude-opus-4-8`. README **Model routing** section synced to match.

## v1.14.0 — 2026-07-23

Added the **Define → Plan → Document** layer — five opt-in general skills adapted from [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (MIT), filling the repo's forward-planning gap (it was strong on execution + reasoning but had no spec/plan/discovery/docs step). **`/interview`** de-fuzzes an underspecified ask one question at a time to ~95% confidence; **`/spec`** writes a PRD (objective, scope, boundaries, acceptance); **`/plan`** breaks it into ordered verifiable tasks + deps and offers the existing `plan-roaster`; **`/adr`** records one decision (the *why*); **`/docs`** produces dual-audience docs (engineer + stakeholder) run through `/humanizer`. `/spec` `/plan` `/adr` write a delimited **PLANNING** block into `docs/context.md` that `/fe-context` now preserves verbatim — so downstream skills execute with intent, not guesses. Overlap avoided: `idea-refine` maps to existing `/ideate`, so it was not duplicated. Also added **`/define`** — a checkpoint-gated orchestrator chaining `/interview → /spec → /plan` (pausing for approval between phases, offering `/ideate` + `plan-roaster`) so an underspecified ask becomes a reviewed spec + task plan in one invoke; and wired the post-build pair as an **opt-in tail of `/parallel-ship`** (offers `/adr` + `/docs` once the verdict is READY TO MERGE). Ordering enforces dependencies: spec precedes plan, adr/docs are post-build. Opt-in only — `/parallel-build` unchanged. Routing wired in `hooks/craftkit-routing.js` (drift guard) + orchestrator table, tiebreaker, and discovery tree in `using-agent-skills.md`.

## v1.13.0 — 2026-07-21

**Token diet for long/subagent-heavy sessions** — no behavior change. (1) Slimmed `hooks/craftkit-routing.js` (~2.3KB→~1.2KB, injected on *every* prompt): dropped the prose that duplicated the always-on routing table, kept the terse gate + the full skill roster (still required by the drift guard) + a pointer to `rules/using-agent-skills.md`. (2) Removed the **Skill authoring rules** detail from the synced always-on `using-agent-skills.md` — relocated to this repo's own `CLAUDE.md` ("Critical authoring rules"), which loads only when editing craftkit source, i.e. exactly when needed. Trims ~2KB from every global session baseline. (3) Compressed the **Model routing** escalation/fusion-panel *process* prose in place (kept triggers + tier table always-on — escalation is global runtime behavior with no reliable on-demand home). Net: lighter per-prompt injection + lighter per-session baseline, no routing/escalation semantics changed.

## v1.12.0 — 2026-07-20

Added **`/think`** skill — curated systems/strategy reasoning router from [tjboudreaux/cc-thinking-skills](https://github.com/tjboudreaux/cc-thinking-skills) (MIT). Six gap-filling frameworks (cynefin, systems, feedback loops, theory-of-constraints, leverage points, second-order) for architecture and complex-system decisions. Deliberately **not** the full 39-skill set — the ~12 overlapping models (first-principles, inversion, red-team, via-negativa, five-whys, …) route to existing `/ideate`, `ponytail`, `adversarial`, `/debug` instead of duplicating them. One routing entry, not seven. Also added a **routing drift guard** to `sync.sh`: every skill in `skills/` must be named in `hooks/craftkit-routing.js` or the sync fails loud — closes the silent-drift seam where a new skill's routing wiring is forgotten (curated orchestrator/native tables stay hand-authored).

## v1.11.0 — 2026-07-20

Added **`/ideate`** skill — parallel divergent ideation adapted from [UditAkhourii/adhd](https://github.com/UditAkhourii/adhd) (MIT). Spawns 5 isolated generators under distinct cognitive frames (first-principles, adversary, steal-from-adjacent, radical-simplicity, …), then a critic scores (`novelty·0.35 + viability·0.40 + fit·0.25`), clusters, flags traps, and deepens the top 3. Gated behind a 3-check pre-flight (open scope · no single right answer · high stakes) — ~10 agent calls, 5–10× a direct answer. Distinct from the fusion panel (generates options vs verifies one decision). Offered as opt-in escalation from `/debug` (fuzzy debugging) and `/parallel-build` (open architecture). Full spawn only on Claude Code + Gemini CLI; degraded/manual on Cursor/Copilot/Codex/Crush.

## v1.10.0 — 2026-07-16

Added experimental **`/team-build`** orchestrator on Claude Code [agent teams](https://code.claude.com/docs/en/agent-teams): the session acts as team lead (escalated model) that scaffolds, writes a dependency-ordered task list, and spawns four everyday-model teammates (impl-a, impl-b, reviewer, tester) that claim tasks and message each other directly. One-file-one-owner law prevents teammate write conflicts; shared wiring files are single-owner tasks. Platform-routed (EVPMR / Android MVP / iOS MVVM-C); FE reviewer reuses the `fe-review` agent definition, native reviewers run the review skills. Explicit invocation only — never auto-routed; requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## v1.9.0 — 2026-07-14

Added sanitized, architecture-agnostic **native mobile skill sets** for Android (MVP + Core framework, Dagger, Gradle DFMs) and iOS (MVVM-C, Bazel/CocoaPods, Quick+Nimble) — each with `patterns`/`scaffold`/`review`/`a11y`/`performance`/`test`/`context` (14 skills). iOS skills that were a gitignored local-only overlay (v1.8.0) are now generalized and shipped publicly. Shared orchestrators (`build`/`review`/`ship`/`fix`/`pr-message`) gained a **Step 0 platform-routing** block that detects RN/web vs Android vs iOS and dispatches to the matching skills. Routing hook + discovery tree updated. For concrete internal module names, drop a project-scoped override at `<repo>/.claude/skills/<name>/`.

## v1.8.2 — 2026-06-25

Fixed a multi-minute stall in parallel workflows. The spawn → synthesize gap left no wait guidance, so the main thread improvised a `grep`/`while` busy-wait on `tasks/*.output` that kept spinning ~12 min after the agents had already come to rest (<2 min). Added a **Do not wait by polling** directive after the spawn paragraph in `parallel-review`, `parallel-ship`, `parallel-build`: the harness auto-wakes the main thread on agent completion — go straight to synthesis, never poll task files.

## v1.8.1 — 2026-06-25

Fixed silent coverage loss in parallel workflows. `fe-a11y` agent was the only one on `model: haiku`; a haiku key 401 killed it and the run reported 4-of-5 agents as if the a11y axis were clean. Aligned `fe-a11y` to `sonnet` and added **Step 5 — Handle agent failures** to the classifier (`using-agent-skills`): a dead agent is now surfaced as a skipped coverage gap and gates the verdict to `INCOMPLETE` instead of `READY TO MERGE`/`DONE`.

## v1.8.0 — 2026-06-25

Removed the iOS skill set from the public package — moved to a local-only overlay (gitignored, kept on disk so local sync still installs it, like `caveman*/` and `cavecrew/`). The skills hardcoded a private codebase's module layout and so don't generalize.

## v1.7.0 — 2026-06-24

Added an on-demand iOS skill set (MVVM-C). _Superseded by v1.8.0 — moved to a local-only overlay; see above._

## v1.6.2 — 2026-06-22

`/pr-message` runs the generated message through the [humanizer](https://github.com/blader/humanizer) skill when installed (`~/.claude/skills/humanizer`) to strip AI-writing tells — optional, preserves markdown structure, no-op on tools without `/humanizer`.

## v1.6.1 — 2026-06-22

`/pr-message` now emits a PR title (`#` heading) alongside the body — concise imperative, matches the branch's conventional-commit prefix when present.

## v1.6.0 — 2026-06-22

Bundled [Jumbo](https://github.com/jumbocontext/jumbo.cli) — per-project memory/context CLI installed globally via `ensure_tools` (npm), alongside RTK. Per-project `.jumbo/` init stays a manual `jumbo` run inside each repo by design. Added to Tooling table.

## v1.5.0 — 2026-06-19

Adopted fusion-fable independence-then-synthesis pattern. Model routing gains fusion panel tier (2× opus → opus judge) with Track A/B classification. Parallel command synthesis upgraded: [CONSENSUS]/[UNIQUE] confidence markers, explicit contradiction surfacing, adversarial findings reframed as blind spots.

## v1.4.0 — 2026-06-19

New `agents/` folder with 7 cold sub-agent definitions (`code-quality`, `fe-review`, `fe-a11y`, `fe-patterns`, `fe-performance`, `adversarial`, `plan-roaster`). Auto-synced to `~/.claude/agents/` on `git pull`. Parallel commands (`parallel-review`, `parallel-ship`, `parallel-build`) updated to spawn agents by name — inline prompt duplication removed (~120 lines).

## v1.3.4 — 2026-06-19

Replaced all ASCII flow diagrams with Mermaid — parallel-review, parallel-ship, parallel-build, classifier examples (A–D), and context flow. Fail/blocked paths added to ship and build diagrams.

## v1.3.3 — 2026-06-19

Added Codex CLI adapter (`~/.codex/AGENTS.md` managed block) and Crush adapter (`~/.config/crush/CRUSH.md` rules + `~/.config/crush/skills/` per-command files). Both wired into sync.sh auto-sync on `git pull`.

## v1.3.2 — 2026-06-19

Escalation model updated to `claude-opus-4-8` across all skills and commands. Context freshness check added to standard load procedure — detects branch/commit mismatch and auto-regenerates `docs/context.md`. Downgraded `fe-a11y`, `fe-scaffold` to cheapest model. Token optimizations: `fe-test` drops redundant context section + git log step.

## v1.3.1 — 2026-06-18

Skill routing upgraded to mandatory gate: classify before every response, announce match or "No skill matched.", added as failure mode #11. Hook injects skill-first reminder every turn for per-turn reinforcement

## v1.3.0 — 2026-06-15

Adopted ponytail: decision ladder in `karpathy-guidelines`, `ponytail:` comment convention, 3 new skills (`ponytail-review`, `ponytail-audit`, `ponytail-debt`), intent-first routing rule

## v1.2.0 — 2026-06-14

Dynamic parallel workflows made default for `/build`, `/review`, `/ship`. README restructured with workflow diagrams, TOC, and token savings examples

## v1.1.0 — 2026-06-13

Added `/parallel-review`, `/parallel-build`, `/parallel-ship` with classifier-based agent selection. Audited and cleaned all skills

## v1.0.3 — 2026-06-10

Added `/pr-message` skill. Enforced `no-unused-vars` in `fe-rules`. Added `tsc --noEmit` verification after any TS change

## v1.0.2 — 2026-06-08

Skill invocation announcements. Fluent tracker mock. Natural language triggers for `/fe-test`. Per-project Copilot agents auto-sync on `git pull`

## v1.0.1 — 2026-06-05

Bash 3.2 support (macOS default). Natural language routing for `/fe-test`. `init-copilot-agents.sh` for per-project `@` agents

## v1.0.0 — 2026-06-01

Three-tier namespace (`rules/`, `skills/`, `commands/`). `code-quality` skill. Inline model escalation. `fe-a11y` skill. Caveman embedded as rule. Skill auto-cleanup on `git pull`
