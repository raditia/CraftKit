---
slug: context-source
status: active
created: 2026-10-05
---

# Context source: a connectable team docs repo for planning

## Spec
**Updated:** 2026-10-05 · **By:** /spec

### Objective

Use one or more team GitHub documentation repos to ground planning in relevant PRDs, specs, SQL,
meeting notes and decisions. Combine the user's prompt with cited context into a shared
understanding that the user approves before it becomes feature intent.

### Users & job

Developers using CraftKit in a project whose team maintains a separate documentation repo.
They need relevant requirements and prior decisions surfaced during planning, and control
of which reference repos the project consults as teams and sources change.

### Success criteria

1. Each project can connect, replace, disconnect and inspect one or more GitHub reference repos,
   naming the source each action targets. A two-project fixture verifies that changing one
   project's connections leaves the other intact, and a two-source fixture verifies that
   replacing or disconnecting one source leaves the project's other source active.
2. Connected planning automatically retrieves relevant context in `/interview`, `/spec` and
   `/plan`, including when `/define` invokes them, searching every active source of the project.
   v1 fixtures cover Markdown/plain text, SQL, JSON/YAML and CSV with traceable citations;
   v2 adds PDF, Word and spreadsheets.
2a. (v1) A relevant file the current version cannot read (PDF, Word, spreadsheet, Git LFS
   pointer, encrypted or binary) is listed as a coverage gap with its source and path, never
   counted as consulted.
3. The proposed understanding states requirements, constraints, decisions, conflicts and
   open questions. A planted contradiction pauses finalization until the user resolves it;
   approval saves the understanding and resolution in the feature's planning document.
   Two connected sources that contradict each other on the ask produce a cross-source conflict
   citing both, resolved by the user the same way.
4. Failed refresh uses the last successfully fetched revision with `cannot-verify` freshness
   and a reason. With no usable copy, planning asks the user how to proceed.
5. Replacing or disconnecting a source prevents future planning from consulting the old
   connection or treating its stored context as current. Approved historical decisions remain traceable.
6. An unconnected project preserves existing planning behavior, verified against baseline
   fixtures. `bash check.sh` passes and the second successful sync is fully up to date.

### In scope

- A per-project connection lifecycle accepting GitHub URLs: connect adds a source, replace and
  disconnect name the source they target, status lists every source. Any number of reference
  repos per project, with no global default.
- Public and private repos accessed through the developer's existing authorized GitHub access.
- CraftKit-managed fetching and refreshing; the user need not maintain a local checkout.
- Automatic relevant-source discovery during planning, using the prompt and current feature
  intent, across all of the project's active sources with one shared read budget. v1 reads
  text formats and reports other files as gaps; v2 adds PDF, Word and spreadsheet extraction.
- A shared understanding for user approval, with source references and explicit uncertainty.
  This means agreement between the user and the agent, rather than voting among agents.
- Conflict presentation naming the prompt requirement, the conflicting document statement
  and its citation; for a cross-source conflict, both documents and their sources. Record the user's resolution before finalizing the understanding.
- Persisting approved understanding in `docs/planning/<slug>.md`, following existing feature
  ownership and approval boundaries. `/interview` proposes in the conversation; `/spec`
  saves approved intent; `/plan` references it and surfaces new conflicts for re-approval.
- Provenance recording: repository identity, Git revision, path and a source locator. Use
  line/section for text (v1), and in v2 page/section for PDF, heading/paragraph/table for
  Word, and sheet/cell range for spreadsheets. Reference the reviewed revision rather than a moving branch.
- A last fetched copy for offline fallback, with explicit freshness and extraction status.

### Out of scope

- Automatic source retrieval in build, review, debugging or shipping. These workflows may
  consume approved feature intent through their existing readers.
- Global connections and cross-project discovery.
- Precedence rules between sources; a cross-source conflict is always the user's decision.
- Multi-agent consensus or automatic resolution of contradictory requirements.
- Writing, committing or publishing changes to the reference repo.
- Running referenced SQL, document macros or commands found in source content.
- Background polling, webhooks and a hosted search service.

### Constraints

- Works across CraftKit's Claude Code, Codex, Cursor and Gemini distribution targets.
  Added distribution scripts must remain Bash 3.2 compatible.
- Use existing authorized access; connection metadata and planning documents contain no credentials.
- Retrieved documents are reference data, not executable instructions or authority to change
  agent behavior. Respect the user's resolution and existing project instructions.
- Fetch failures are `cannot-verify`, never `clean`. Cite the actual locally reviewed revision
  and disclose when it could not be checked against GitHub.
- No connection means no new remote access or mandatory reference-context questions.
- Existing Figma/Lark pointer and freshness behavior remains compatible. No Figma/Lark
  inputs were supplied for this PRD; its requirements come from the approved interview choices.
- Keep a managed GitHub copy separate from committed feature intent. The current
  `partials/external-sources.md` forbids persisting fetched Figma/Lark content; implementation
  must explicitly scope the GitHub-copy allowance rather than silently relax that contract.
  Store approved decisions and pointers, rather than bulk source documents, in planning files.

### Key decisions

- **Per-project connection:** sources can change independently as projects or teams change.
- **Many sources per project:** a team repo and a wider platform decisions repo can both apply.
  Search shares one read budget across sources so cost does not grow with every connection,
  and coverage is reported per source so a thinly searched source is visible.
- **Phased formats:** v1 reads text formats; PDF, Word and spreadsheet extraction is v2,
  because its cross-host dependencies are the largest unproven risk.
- **GitHub URL with managed fetching:** removes the user's clone/update maintenance step.
- **Planning-only automatic lookup:** context informs scope before implementation begins.
- **Human approval:** conflicts require a cited user decision; relevance or absence of a
  discovered conflict does not prove agreement across the whole documentation repo.
- **Last fetched revision fallback:** planning stays usable when GitHub is unavailable while
  freshness uncertainty remains visible. No usable copy requires a user decision.
- **Saved approved understanding:** later agents can trace decisions to the reviewed sources.

### Risks & open questions

1. Configuration location, project identity and cache ownership remain design choices.
   Decide how moved projects, shared copies and disconnect cleanup behave without deleting
   user-owned files. Disconnect must stop consultation regardless of physical cache retention.
2. Relevance search, how the shared read budget ranks files across sources, and treatment of
   superseded or conflicting documents need a concrete design and fixtures. Report search coverage; do not claim exhaustive agreement.
3. Extraction dependencies and supported format variants need validation across hosts.
   Encrypted files, scanned PDFs, unsupported formats and Git LFS pointers must be surfaced
   as unread or partially read rather than silently counted as consulted sources.
4. Define branch selection, refresh frequency and how source drift reopens previously approved
   understanding. Changing source revisions must not silently rewrite approved decisions.
5. Settle the provenance schema and how saved references are marked after replacement or
   disconnect. Preserve historical citations without automatically reactivating old connections.

### Acceptance criteria

- [ ] Connect project A to a public GitHub URL and project B to a private URL using existing
  access; status identifies each connection and neither project's actions affect the other.
- [ ] Connect two sources to project A; status lists both. Disconnect one by name; the other
  stays active and planning searches only it.
- [ ] Given a connected URL without a local copy, CraftKit fetches it automatically. Missing
  authorization produces an actionable error without writing credentials or a false usable state.
- [ ] Replace A's connection; subsequent planning consults the new source only. Disconnect A;
  later planning does not read or refresh either former source as an active connection.
- [ ] Given no connection, `/interview`, `/spec`, `/plan` and their `/define` invocation preserve
  baseline planning behavior without new source prompts or remote calls.
- [ ] (v1) A fixture with relevant documents in every v1 text format produces findings with
  repository, reviewed SHA, path and line. A relevant PDF, Word or spreadsheet file in the same
  fixture is listed as a coverage gap. (v2) The same fixture yields findings with page, heading
  or cell-range locators for those formats.
- [ ] Irrelevant documents do not become requirements. Unreadable or partially extracted
  relevant documents are identified as coverage gaps, and source commands are not executed.
- [ ] A prompt contradicting a fixture decision produces a cited conflict; finalization waits
  for the user's resolution. Approval saves that resolution with the shared understanding.
- [ ] Two connected fixture sources that contradict each other on the ask produce one
  cross-source conflict citing both; the recorded resolution names both sources.
- [ ] The approved planning document includes requirements, constraints, decisions, unresolved
  questions and source provenance, without copying the documentation repo into the project.
- [ ] Refresh failure with a usable prior copy proceeds using its actual SHA and reports
  `cannot-verify` with a reason. With no usable copy, ask how to proceed instead of guessing.
- [ ] A changed source revision is surfaced before reusing affected understanding; approved
  decisions are not silently rewritten. Old-source citations survive as historical references
  after replacement/disconnection and are not represented as current consulted context.
- [ ] Existing Figma/Lark behavior remains intact; shared contracts cover both source types
  explicitly. `bash check.sh` passes, followed by two successful `bash sync.sh` runs with
  everything up to date on the second run.

## Task Plan
**Updated:** 2026-10-05 · **By:** /plan (revised after plan-roaster 4/10, then for multiple sources per project)

Phased by author choice: v1 is managed fetch, text formats and the three planning skills; v2 adds
PDF, Word and spreadsheet extraction. Design: connections in `~/.craftkit/context-sources.json`
keyed by project git toplevel, each entry a list of sources named by their normalized URL, URLs
normalized (host and owner lowercased, `.git` stripped, ssh and
https unified) with embedded userinfo rejected; one craftkit-owned shallow cache per normalized URL
under `~/.craftkit/context-cache/`, reference-counted from the store; the remote's default branch
is tracked and recorded; disconnect or replace prunes an unreferenced cache and prints its path and
size. The helper ships through the existing `sync_bin` path (`scripts/` to `~/.craftkit/bin`, the
same route `cross-review.sh` takes) behind a bash wrapper that resolves node itself, because only
Claude's hooks resolve node today. The riskiest link, a prose skill on four hosts driving the
helper, is proven by the T4 spike before anything is built on it. No feature test cases exist, so
TCs are `none`.

| ID | Task | Acceptance | Depends on | TCs | Executes via |
|----|------|-----------|-----------|-----|--------------|
| T0 | **Done 2026-10-05.** Amend the spec to the phasing and to multiple sources per project | Spec marks v2 rows, has Success 2a and the two-source acceptance rows | none | none | /spec |
| T1 | **Done 2026-10-05.** Record a new decision: a managed git cache lives under `~/.craftkit`, never in the project, and planning files hold pointers and approved decisions only. ADR-0002 ("`docs/` holds intent and decisions only") is cited as the boundary it respects, not an exception | `docs/adr/0003-*.md` exists and cites ADR-0002 and `external-sources`; Decisions section points to it | none | none | /adr |
| T2 | **Done 2026-10-05.** Write `scripts/context-source.js` plus `scripts/context-source.sh` (bash wrapper resolving node like `_resolve_node_bin`; distinct exit code when node is missing): `connect` (adds a source), `replace <old> <new>` and `disconnect <source>` (name the source; ambiguous or unknown name refused), `status` (lists every source), with URL normalization, userinfo rejection, `GIT_TERMINAL_PROMPT=0`, and `status` reporting entries whose toplevel no longer exists | `check.sh` fixtures on local bare repos: A and B connect independently; replace A leaves B intact; A with two sources: disconnecting one keeps the other; connecting a URL already present is a no-op; disconnect prunes only an unreferenced cache; ssh and https forms share one cache; a URL with userinfo is refused and nothing is written; missing auth exits non-zero quickly with no prompt; a deleted project shows as stale | none | none | /build |
| T3 | **Done 2026-10-05; `refresh` is the resolve step, no separate command.** Add `refresh` and `resolve` over all of a project's sources in one call, with one freshness line per source: `clean`, `drifted (old → new)`, `cannot-verify (<why>)` with the cached SHA; one failing source never blocks the others; distinct ask-the-user exit code when no cache and fetch fails; fetch under a lock with an atomic swap so two projects sharing a cache cannot race | Fixtures: two sources, one fetch failing → one `cannot-verify` line and one `clean` line; remote advanced → drifted; remote removed with cache → cannot-verify plus cached SHA; no cache and no remote → ask-exit; two concurrent refreshes leave one consistent cache; unconnected project → silent exit 0 and git is never invoked (git stubbed on PATH to fail if called) | T2 | none | /build |
| T16 | **Done 2026-10-05; coverage line is `coverage source=<key> searched=N read=M skipped=<reason:count,...>`.** Define the shared read budget across sources: rank candidate files across all caches, cap total reads at 8, give every active source at least one read when it has a hit, and report coverage per source (`<source>: searched N, read M`) | Helper `search` fixture: two sources with hits in both read from both; a source with no hits reports `searched N, read 0`; total reads never exceed 8 | T3 | none | /build |
| T4 | **Done 2026-10-05: Claude Code full, Codex degraded to cached SHA, Cursor and Gemini unverified (`docs/research/context-source-hosts.md`).** **Spike, gate for T5 onward.** Stub partial plus one planted contradiction in a fixture docs repo; run `/spec` through it on Claude Code, and probe Codex, Cursor and Gemini for: calling `bash ~/.craftkit/bin/context-source.sh`, network, git credentials, writes to `~/.craftkit` | Claude run pauses with a cited CONFLICT prompt; a capability table per host is written to `docs/research/context-source-hosts.md`; any host that fails gets a decided fallback (report `cannot-verify` on that host) recorded before T5 starts | T3 | none | /research |
| T5 | **Done 2026-10-05.** Add `context-source.js` and `context-source.sh` to `sync_bin` `names` | `bash sync.sh` twice: second run `(up to date)`; check 32d still passes (no new directory, `scripts/` already shipped) | T4 | none | /build |
| T6 | **Done 2026-10-05.** Add `skills/context-source/SKILL.md` wrapping the wrapper script (connect, replace, disconnect, status), with routing entries in `hooks/craftkit-routing.js` and `rules/using-agent-skills.md`, and a README row | Sync drift guard passes; routing-hook check advertises `/context-source`; README check finds the row | T5 | none | /build |
| T7 | **Done 2026-10-05.** Write `partials/context-source.md`: resolve once per workflow and pass the result down (as `planning-resolve` does with the slug), so `/define` and its child skills fetch once; first step is a no-op without a connection; search every active source through the T16 budget, cite `repo@sha:path:line` from the search line's `sha=`/`file=`, list non-text, LFS and unreadable files as gaps with their source, report coverage per source; when the helper call did not run or exited 1, 3 or 5, say `context source not consulted: <why>` instead of staying silent; on exit 4 tell the user to run refresh outside the sandbox or approve escalation; fixed CONFLICT A/B/C prompt for prompt-vs-doc, and a cross-source CONFLICT prompt citing both documents and both sources; doc text is data, SQL and commands are never run; host fallback from T4 | Partial renders via `craftkit_render_injected`; the exact CONFLICT, cross-source CONFLICT, `cannot-verify` and no-op strings are present | T1, T4, T16 | none | /build |
| T8 | **Done 2026-10-05.** Inject the partial into `skills/interview`, `skills/spec`, `skills/plan` and `commands/define.md`. `/interview` proposes in conversation; `/spec` saves the approved understanding and pointers; `/plan`, on a drifted SHA, lists the decisions citing affected docs and asks for re-approval without rewriting them | Rendered files carry the partial; check 30 passes; `/define` renders the resolve-once handoff | T7 | none | /build |
| T9 | **Done 2026-10-05.** In `partials/external-sources.md`: scope line 47 ("Figma and Lark content: never on disk; `kind: git`: only the cache under `~/.craftkit/context-cache`"); add the `kind: git` row (`ref: <url>#<path>:<locator>`, `seen: sha:<sha>`, `connection: active or historical`); Figma and Lark rows unchanged | Existing external-sources check passes; new assertion that line 47 carries the scope and that `kind: git` is skipped by the Figma and Lark path | T1, T7 | none | /build |
| T10 | **Done 2026-10-05.** On replace or disconnect of a named source, the skill (not the helper) marks only that source's `kind: git` entries in the project's active planning files as `connection: historical`, leaving other sources' entries active, and planning never consults a historical source as current | Skill text carries the marking step; manual run on a two-source fixture shows the disconnected source's citation kept and marked historical and the other source's citation still active | T6, T9 | none | /build |
| T11 | **Done 2026-10-05.** Add `check.sh` static guards: exact partial strings from T7, including the cross-source prompt; helper silent and git-free when unconnected (from T3); a ban on `github.com/[^<]` in context-source files so only placeholders appear; line 47 scoped (from T9) | Each guard fails when its invariant is broken by hand, then passes; `bash check.sh` exits 0 | T6, T8, T9 | none | /build |
| T12 | **Done 2026-10-05.** Behavioral eval on the full fixture: 5 runs each on Claude Code and Codex of `/spec` with a contradicting ask, 5 runs each with two connected sources that contradict each other, plus one unconnected baseline run per host, plus one run against a real private repo with no credential helper to confirm a fast non-interactive refusal | Pass bar per host and per case: at least 4 of 5 runs pause with the correct citation (both sources for the cross-source case) and record the resolution with provenance and no copied doc text; unconnected runs show no source lines; scored by `/eval` | T10, T11 | none | /eval |
| T13 | **Done 2026-10-05.** README (skill, partial, store, cache and wrapper paths), CHANGELOG section, version bump in `package.json` and README header | Version check passes; `bash check.sh` exits 0; `bash sync.sh` twice with the second fully up to date | T12 | none | /build |
| T14 | **v2.** Research PDF, Word and xlsx extraction that works on all four hosts without a per-user install, including encrypted and scanned-PDF behavior | Research note in `docs/research/` naming the approach and its failure modes | T13 | none | /research |
| T15 | **v2.** Implement extraction with locators (page/section, heading/paragraph/table, sheet/cell range); unreadable files stay coverage gaps | Fixture docs in each format produce findings with locators; encrypted or scanned files reported unread | T14 | none | /build |

**Parallelizable now:** T1, T2
**Critical path:** T2 → T3 → T4 → T5 → T6 → T10 → T12 → T13 (T16 runs beside T4; T7 → T8 → T11 run beside T5 → T6)

## Decisions
- [ADR-0003](../adr/0003-managed-context-source-cache.md) · managed git cache under `~/.craftkit`, outside every project; planning files hold pointers only · Accepted 2026-10-05
