# Changelog

Every notable change to craftkit, newest first. Each entry is what the release actually
changed and why it was needed — the reasoning is kept because most of these fixes exist to
stop a bug that had already shipped and gone unnoticed.

Versions are cut by `.github/workflows/release.yml` on push to `main`: it reads the version
from the README header and this file's matching `## <version>` section for the release notes.

## v1.30.0 — 2026-08-31

**Two hooks that refuse, because a rule the agent promises to follow is worth less than a gate that stops it.** The routing hook has always injected the skill-first table as context, and context is text: an agent can read it, announce `/ship`, and then run a repo-wide formatter instead of the scoped lint the skill named. That happened, and the only reason it surfaced was the user noticing. `UserPromptSubmit` cannot prevent anything, so the enforcement half now lives on the two events that can.

`hooks/gate-skill-first.js` (`PreToolUse` on the edit tools) returns `ask` when a source file is edited with no `Skill` call in the turn, and names the skills that fit the file's platform. `hooks/gate-verify-on-stop.js` (`Stop`) blocks a turn that edited source and ran no verification command, resolving the required command from the project: `check.sh` at the root if present, otherwise a typecheck plus a lint for a `package.json` project, and nothing at all when neither exists. It respects `stop_hook_active`, so it blocks once and never loops.

Both scope to the **current turn**, read through the shared `hooks/craftkit-transcript.js` so they cannot disagree about where the turn began. Per turn rather than per session is the point: a single skill call at session start would otherwise buy a session-long pass, which is the same silent bypass wearing a receipt. A slash command you typed yourself arms the gate as well as a `Skill` call does, since it is one.

The skill gate asks **once per unrouted turn**, not once per edit. It fires per tool call, so a ten-edit turn would have cost ten prompts, and a gate that produces a wall of prompts is a gate you learn to click through, which is the same bypass by a slower route. The first ask stamps the turn (keyed by the transcript entry's uuid, since hashing the prompt text alone collides on a repeated "continue") and the rest of that turn passes. The tradeoff is explicit: denying the first edit lets the remainder of the turn through, because the denial itself is the redirect.

Both **fail open**: unreadable transcript, malformed stdin, or a project with no gate command all pass. A gate that guesses does more damage than one that abstains, and check 23 is behavioral for exactly this reason, since a gate that silently returns `{}` is indistinguishable from a gate that works until the day you needed it. `CRAFTKIT_GATE=off` disables both.

Worth noting what this reaches that the routing hook never could: `UserPromptSubmit` does not fire for subagents, so no routing context reaches one, while `PreToolUse` does. An unrouted subagent edit was previously invisible.

Caught while testing the gates on their own diff: editing through the shell (`sed -i`, a heredoc, `tee`) writes a file with no `Edit` tool call, so **neither** gate saw it, which is the bypass an agent skipping a skill is most likely to take. The Stop gate now takes its file list from `git status` whenever the turn's commands look write-ish, and only then, so a tree that was already dirty before the session cannot gate a read-only turn. The skill gate stays tool-scoped: a `PreToolUse` matcher on `Bash` would have to guess which commands write, and it would fire on every `sed` in a pipeline. That gap is documented rather than papered over.

Subagents needed handling in both directions, found by auditing the change rather than by using it. A subagent gets its own transcript under `<session>/subagents/`, with `isSidechain` on every entry, so the parent's `Skill` call is not in it: the skill gate would have prompted on every edit a `/parallel-build` implementer makes, in a context where a background agent may have nobody able to answer. Sidechain turns pass, and routing stays the parent's job. The mirror of that leak is worse and less obvious: a parent that delegates all its edits shows no edits in its own transcript, so the Stop gate saw a clean turn. A turn that spawned an agent now takes its file list from `git status`, the same treatment shell writes already got.

**`adapters/claude.sh` installs hooks from a table, not from one hardcoded constant.** `_CRAFTKIT_HOOKS` carries `script%event%matcher%statusMessage` (delimited by `%` because a `PreToolUse` matcher owns the pipe), and wiring generalizes over it: a matcher belongs to the settings *entry* rather than the hook, so an entry with a different matcher is never reused, which would silently widen or narrow which tools a gate sees. Unwiring removes only commands naming our own scripts and collapses only entries it emptied, leaving hand-added hooks like a local formatter guard untouched. The stale-interpreter repair from v1.28.x now applies to every hook instead of just the router. **Check 24** holds the both-directions invariant that check 13 holds for adapters: a script in `hooks/` that no table entry names is never installed, and a table entry with no script registers a command that fails on every event it fires for.

## v1.29.1 — 2026-08-26

**The managed-block marker is now `CRAFTKIT`, not `AGENTIC-SKILLS`.** The wire format had disagreed with the product name since before this repo was called craftkit, leaving a reader no way to tell whose block was in their `CLAUDE.md`. Renaming the constant alone would have been the graphify bug on purpose: the marker is already written into every user's `CLAUDE.md`, `GEMINI.md`, and `AGENTS.md`, so an adapter pointed at a new literal cannot find the old block, takes the append branch, and writes a second one that loads forever as stale always-on rules. `sync.sh:craftkit_migrate_markers` therefore rewrites the pair in place before any adapter looks, and is idempotent because nothing is left to match afterwards. The new marker also drops its em-dash, retiring one of the three check 19 exemptions.

That rename then produced its own failure live: the edit silently no-op'd on two of three adapters, so the migration renamed the block while Claude and Codex kept hunting the retired literal, and both files ended up with duplicate blocks. Fixed, and **check 22** now greps `adapters/` for the retired marker so a partial application cannot ship. `CLAUDE.md` gains the rule that made it obvious in hindsight: a marker rename migrates the block on disk first, and applies to every adapter in one change.

**`sync.sh` prunes orphaned staging directories.** Retiring an adapter deleted its state files but left its staging dir behind, so `~/.craftkit/copilot` and `~/.craftkit/crush-rules` were still on disk months after the v1.25.1 removal. Staging dirs are ours and rebuilt every sync, so any whose prefix matches no live adapter is an orphan. Pruned by prefix rather than against a retired-list, so the next retirement self-cleans.

**Check 5 no longer passes vacuously on a misspelled `craftkitInject` field.** It greps `^craftkitInject:`, so a typo in the *field* left `_list` empty, the target loop skipped, and the agent installed carrying no injected body at all: `fe-review` would review without the EVPMR constraints it exists to enforce, silently and indefinitely. Any frontmatter key mentioning inject that is not exactly `craftkitInject` now fails. The assertion sits deliberately above the empty-list `continue`, because a misspelled field is precisely what makes the list empty, and the first attempt at this check was placed below it and so was never reached.

## v1.29.0 — 2026-08-26

**`/grill` learns the seven things the upstream docs teach and the skill never said.** The skill was adapted from mattpocock/skills `grilling` + `grill-with-docs`, but only the mechanism came across: design tree, frontier, question format, facts-vs-decisions. Reading those docs in full surfaced seven behaviors that change what a session does, all now in `skills/grill/SKILL.md`. **Ungrillable questions** are the big one: how a layout looks or an interaction feels cannot be settled by talking, and talking anyway is where sessions balloon, so they get named, parked, and routed to `/ideate` or a throwaway build. The round now states that it is answerable by number alone. The recommendation must be worded so agreeing with it never means answering "no" to the question above it, a known upstream rough edge. The frontier is the agent's judgement rather than a computed graph, so two coupled questions can share a round, and the fix is to reopen that branch next round instead of defending it. Blanket agreement gets challenged, because a user who answers "agreed" to every question has decided nothing and the plan carries certainty it has not earned. A frontier past roughly a dozen questions means the scope is too big, so propose splitting rather than grinding. One-at-a-time is supported on request, not merely tolerated.

**Em-dashes are gone from the repo's prose, and a gate keeps them gone.** The em-dash is a recognizable machine-writing tell, and roughly 1,600 of them across 78 files were rewritten by hand, one sentence at a time, into a comma, colon, semicolon, period, or parentheses as each sentence wanted. Not a mechanical substitution: a table cell that meant "not applicable" became `n/a`, a definition list became `Term: definition`, and `## Step 3 — Implement` became `## Step 3: Implement` across every orchestrator. Verified: `bash -n` on all seven shell files, `node --check` on the routing hook, and `check.sh` clean.

Three classes keep their em-dash because they are wire format, not prose, and new **check 19** exempts them by line pattern rather than by file, so a genuine slip on the same line still fails. The `## vX.Y.Z — date` heading is the format `release.yml` and `check.sh` both parse, and `CHANGELOG.md` is a historical record that is never rewritten. The two managed-block markers, `BEGIN AGENTIC-SKILLS` and `BEGIN CRAFTKIT-INJECTED-RULES`, are already written into every user's `CLAUDE.md`, `GEMINI.md`, and `AGENTS.md`: changing either string would stop the adapters finding the existing block, and they would append a second one and orphan the first forever. That is the bug the exemption exists to prevent, found while sweeping rather than after shipping.

Check 19 builds the character from its UTF-8 bytes with `printf` so `check.sh` can scan itself without matching its own source. The convention is written down as a writing lever in `CLAUDE.md`, next to the no-op test and the leading-words rule it belongs with.

**Ponytail rubric widened from upstream v4.9.0.** A drift check against `dietrichgebert/ponytail` found three tag descriptions that had grown more inclusive than ours. `native:` covered only a dependency doing the platform's job and now covers hand-written code doing it too. `yagni:` gains "config nobody sets" as a third concrete case. `delete:` gains "speculative feature", which is blunter than "flexibility nothing uses". Added with them: a finding must name its replacement, the stdlib function or platform feature or shorter form, because `/ponytail-review` already demanded that while the always-on rubric the writing side authors under did not, so the self-pass was the weaker half. One table in `rules/karpathy-guidelines.md` carries all of it: the two ponytail skills and the cold agent only name the tags and defer meanings there, and the agent receives the table live through `craftkitInject`, so a single edit reaches every consumer.

Checked and found already current: upstream's `ponytail:` marker narrowing (their #120) demanded a real corner-cut with a known ceiling, which this repo already required, in more specific terms and with examples. Their new FAQ entry confirms ponytail and caveman are complementary rather than overlapping, which is how they are wired here. `narrate:` remains a craftkit extension; upstream ships five tags, not six.

Declined, with reasons: `ponytail-gain` prints upstream's own benchmark medians rather than anything measured here, so it changes no engineering behavior. `ponytail-help` duplicates what the routing hook, README, and skill tree already carry, which trips this repo's duplicate-concept check. The `lite`/`full`/`ultra`/`off` mode system collides head-on with the caveman plugin, which already owns those level names in this setup, and ponytail is always-on here through `karpathy-guidelines` rather than mode-switched. The fifteen new tool adapters are outside the four this repo syncs by choice.

**graphify wired into `/debug` and `/fe-performance`, as a tool rather than as content.** [graphify](https://github.com/Graphify-Labs/graphify) parses a repo into a knowledge graph with tree-sitter: deterministic, local, no embeddings and no vector store, with every edge tagged `EXTRACTED` or `INFERRED` so inference is visible. `/debug`'s Isolate step now queries the graph first (`graphify affected` for blast radius, `export callflow-html` for the path in) and falls back to `cavecrew-investigator` when no graph exists, which turns a grep sweep into an edge traversal. `/fe-performance`'s barrel-import audit uses the same query to name what a barrel actually drags in, instead of reasoning it out against the `fe-rules` Imports rule. Its install machinery is deliberately not adopted: it targets the same four destinations craftkit's adapters already own, so it is a Tooling dependency like RTK, Caveman, and Ponytail.

**The managed CLAUDE.md block now survives a third-party tool eating its BEGIN marker,** and **check 21** proves it against a fixture. graphify's global mode writes a `## graphify` section into `~/.claude/CLAUDE.md`, and its uninstall deletes from that heading to the next `## ` heading. Our block opens with an HTML comment followed by rule bodies full of `## ` headings, so the strip took the BEGIN marker and the first rule's frontmatter with it and left an orphaned END. `_rebuild_claude_md` then failed its BEGIN-present test, took the append branch, and wrote a *second* block, leaving the orphaned copy loading as always-on rules with nothing to signal it. Reproduced by running graphify's own `_remove_marker_section` against a simulated file before writing the fix. The guard drops the orphaned END and reports that stale text may remain above it, rather than guessing which lines were ours: outside the markers, our content and the user's are indistinguishable by position. Project-scoped installs, graphify's default, never touch the file at all.

**Check 20 catches dangling in-page anchors.** GitHub derives an anchor from heading text, so the em-dash sweep above retargeted three README headings and broke four TOC links: `" - "` collapses to `--` in a slug but `", "` collapses to `-`, so each link kept a dash its heading no longer had. Nothing failed loudly, because a dead anchor just scrolls nowhere. Found by diagnostics after the sweep was already reported clean, which is why it is now a gate.

Reviewed and rejected in the same pass: `gvzdv/claudish-to-english`. It is a `MessageDisplay` hook that pipes every assistant message through a second model with a one-line "make it simpler" prompt, so there is no rubric to port, and a second display-layer rewriter would fight the caveman plugin's hooks over the same text. The rubric-based equivalents already here are `skills/humanizer` and the writing levers. Encoding the tell as an authoring rule costs nothing per message; a second model costs one call per message.

## v1.28.1 — 2026-08-19

**Restore the plan gate on model tiers.** v1.28.0 replaced plan detection with a derivation — "the top three entitled families become cheapest / everyday / escalate" — and it looked equivalent, because it reproduced both historical plan rows exactly. It was not. The signal it leaned on to tell the plans apart was the presence of a fable entry, and on the account it was built against that entry comes from `additionalModelOptionsCache`: a *picker* list, not an access list (`claude-fable-5` itself reads `entitled: false` there). Advertise fable to a Pro account — upsell, trial, "available on a higher plan" — and its everyday tier silently jumps from sonnet to opus, on a repo whose whole point is that skills route by tier.

The mistake was throwing out plan detection along with the hardcoded ids. The ids were what went stale every release; the plan signal never did, and `oauthAccount.organizationType` still carries it.

- **Plan picks the tier window, entitlements pick the ids inside it.** Enterprise reaches the frontier family (sonnet / opus / fable → everyday is opus); personal caps below it (haiku / sonnet / opus → everyday is sonnet) regardless of what the picker advertises. Unreadable config or unrecognized plan falls to the personal window — the conservative side. Ids inside the window are still the newest entitled version of each family, so a release still needs no edit here: an `opus-6` displaces `opus-5` on its own.
- **`check.sh` check 18 now asserts both windows**, including the exact regression: a personal plan shown fable in the picker must still resolve `everyday=sonnet`. Verified the assertion bites by removing the cap — it fails on precisely that case and on the matching cheapest tier.
- The injected tier line names the detected plan, so a wrong window is visible in the context rather than only in behavior.
- README's resolution diagram gained the plan branch, and both diagrams re-rendered through mermaid-cli.

## v1.28.0 — 2026-08-19

**Model tiers are resolved from account entitlements instead of written down.** Opus 5 shipped, and updating for it meant editing 17 files — the plan table in `rules/using-agent-skills.md`, the same table in `README.md`, 13 skill `**Model:**` lines, `commands/{define,fix,pr-message,team-build}.md`, and two constants in the hook. That treadmill has run on every Claude release since `claude-opus-4-8`, and its failure mode is silent: a missed line keeps routing work to a retired model with a plausible-looking label.

- **`hooks/craftkit-routing.js` derives the trio instead of hardcoding it.** Claude Code already caches the real answer in `~/.claude.json` — `modelAccessCache` lists every model with an `entitled` flag, `additionalModelOptionsCache` carries extra picker entries (a base id can read `entitled: false` while its `[1m]` variant is selectable, so the two are unioned). The hook takes the newest entitled version per family, ranks families `haiku < sonnet < opus < fable`, and injects the top three as cheapest / everyday / escalate. Both retired plan rows fall out of that rule unchanged — no fable → haiku/sonnet/opus, fable → sonnet/opus/fable — so the email-domain plan guess is gone, replaced by what the account can actually run. A version bump inside a known family is now a no-op here; only a brand-new *family* name touches `FAMILY_RANK`, since a name alone cannot say where it ranks.
- **Skills and commands name a tier, never a model id.** 17 hardcoded ids removed; the injected line is authoritative, and agents spawn on the family alias (`sonnet`/`opus`/…), which self-updates to the newest model in its family — which is why the `model: sonnet` pin in every `agents/*.md` frontmatter was already release-proof and stays.
- **Two new `check.sh` gates hold the property.** Check 17 fails on any `claude-<family>-<digit>` id in `rules/`, `skills/`, `commands/`, or `agents/`, so the treadmill cannot be reintroduced by hand. Check 18 is behavioral — it runs the hook against four fixtures (both historical plan shapes, a picker-only fable, an `opus-6-2` release, an unreadable config) because a rank or parse regression still emits a plausible tier line and would otherwise pass a grep.
- **The other three tools, same property by their own means** (researched against primary docs — `docs/research/self-updating-model-ids.md`, the repo's first research note). The Claude fix left Gemini/Cursor/Codex pinned, and the check above was vendor-scoped, so nothing caught that **`codex-mini-latest` had been retired since 2026-02-12** — six months dead in the routing table — or that `o3` shuts down 2026-12-11. Gemini CLI turns out to ship the same mechanism Claude Code does: first-party `auto`/`pro`/`flash`/`flash-lite` aliases resolving against CLI constants *plus* the account's preview entitlement (`flash-lite` already crossed 2.5 → 3.1 on its own), so the table takes those rather than the API's `gemini-*-latest`, which can hot-swap onto a rate-limited preview build against Google's own production guidance. OpenAI exposes no self-updating coding id at all — `gpt-5.6` looks like an alias but pins the *minor* version — so Codex CLI now leaves `model` unset and lets its server-refreshed catalog resolve the default, carrying the tier in `model_reasoning_effort` instead. Cursor has no committable model selector on any documented surface, so that row says so instead of naming ids nobody can set. Check 17's regex widened to all four vendors accordingly.

- Unreadable entitlements fall back to the family aliases `haiku`/`sonnet`/`opus` and say so in the injected line, rather than guessing a versioned id that may not exist on the account.

## v1.27.0 — 2026-08-11

Added the `LICENSE` that `package.json` had been promising for 26 releases, plus `CONTRIBUTING.md`.

Started as a question about why GitHub shows only one tab on the repo page. It shows tabs for a fixed allowlist of community health files (`README`, `CODE_OF_CONDUCT`, `CONTRIBUTING`, `LICENSE`, `SECURITY`, `CITATION`) — `CHANGELOG.md` is not on it and never gets a tab, so `v1.26.0`'s split was fine as-is. But checking which of those files existed surfaced a real problem.

- **`package.json` declared `"license": "MIT"` with no `LICENSE` file anywhere in the repo.** npm advertised MIT while the grant existed nowhere, GitHub could not detect or display it, and four MIT-licensed upstreams had been adapted without the notice their license requires. A license claim nobody can read is not a license.
- **`LICENSE` added** — MIT text, `Copyright (c) 2026 Gusti Raditia Madya`, plus a third-party section naming each adapted upstream and what it became. The four attributions were verified against the files themselves rather than from memory: `mattpocock/skills` → `skills/{grill,research,handoff}` + CLAUDE.md's writing levers; `addyosmani/agent-skills` → `skills/{adr,docs,interview,spec,plan}`; `UditAkhourii/adhd` → `skills/ideate`; `tjboudreaux/cc-thinking-skills` → `skills/think`. Exact upstream copyright lines are not reproduced because they were not available to copy verbatim — the section invites those authors to open an issue if they want their notice included as written.
- **`CONTRIBUTING.md` added**, carrying the gate (`check.sh` exit 0, second `sync.sh` reporting no work), the full list of what `check.sh` catches, the release procedure, and the conventions that bite. The README keeps a three-line pointer instead of the buried section it had. Authoring rules stay in `CLAUDE.md` deliberately — that file is loaded into every session working in this repo, so it is the copy that actually gets followed.
- **`check.sh` check 16** — a declared license must have license text behind it, and the file must name that license **in its header**. The header restriction is the point: an initial version grepped the whole file and passed a deliberately mismatched `Apache License` header, because "MIT-licensed" in the third-party attribution block satisfied it. Caught by testing the branch rather than trusting it; all three branches (no claim, no file, header mismatch) verified failing before passing.
- Skipped `CODE_OF_CONDUCT.md` and `SECURITY.md`: for a single-maintainer skills repo they are boilerplate nobody reads, which is what the ponytail rubric exists to catch.

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
