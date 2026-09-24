---
slug: mcp-context
status: active
created: 2026-09-24
---

# MCP-aware context and test-case-driven development

## Spec
**Updated:** 2026-09-24T00:00:00Z · **By:** /spec

- **Objective:** skills today see only git, so requirements that live in Figma and Lark reach
  the build by memory or not at all. Make those sources first-class, pinned, freshness-checked
  context, turn them into dev-approved test cases, and make every build, test and eval step
  work against those cases, without one feature's context leaking into another's.
- **Users & job:**
  - Developer running craftkit skills in a feature repo: build against every stated
    requirement and behavior, know when the design or doc moved under them.
  - QA / PM: read the published test cases (Lark or Excel) and send feedback, never edit the
    master copy.
- **Success:**
  1. A Figma or Lark source changed since its recorded marker is reported `drifted`, and every
     TC citing that source flips to `needs-review` (proposed, then written on confirm).
  2. With no MCP server connected, auth expired or rate-limited, every touched skill reports
     `cannot-verify` for that source and otherwise behaves as before (git-only). With no slug
     passed in, a context skill skips the sources step entirely, so standalone output is
     unchanged.
  3. `/plan` maps every task to at least one approved TC id; `/build`, `/parallel-build` treat
     only `approved` TCs as requirements and list `draft` / `needs-review` ones as unverified.
  4. Each approved TC with `automation: jest|junit|quick` gets exactly one test, named with the
     TC id, in `/fe-test`, `/android-test`, `/ios-test`; `manual` TCs are listed, not tested.
  5. `/eval` receives the approved TC set as acceptance criteria.
  6. Excel export produces one `.xlsx` with id, title, steps, expected, status per TC.
  7. With two features in the repo, no skill or agent fetches a source or reads a TC file that
     belongs to the other feature's slug.
  8. A source whose marker cannot be computed reproducibly (spike T0) reports `cannot-verify`,
     never `drifted`; `seen` is written only by `/spec` (first record) and `/test-cases` (on a
     confirmed re-review), so a handled drift returns to `clean`.
  9. `bash check.sh` exits 0, with new checks that fail before the change: resolver exclusion,
     context skills do not inject `planning-resolve`, intent readers do, no concrete tool ids.
- **In scope:**
  - `sources:` list in the intent file: Figma and Lark pointers, each with a `seen` marker.
  - `partials/external-sources.md`: read-time freshness check (clean / drifted /
    cannot-verify), scoped fetch, git-only fallback. Marker checks run once per workflow in
    Phase 0 (cheap metadata only); content is fetched only on drift, to stay inside Figma MCP
    rate limits. Injected into `fe-context`, `android-context`, `ios-context`, `spec`, `plan`,
    `fe-design`, and the build orchestrators. Context skills receive slug + sources from the
    caller and never resolve intent themselves.
  - New `/test-cases` skill: generate from sources, re-review on drift (sole `seen` writer after
    `/spec`), export Excel via the installed `xlsx` skill.
  - `planning-resolve` injected into every intent reader that lacks it today: `build`,
    `parallel-build`, `parallel-review`, `parallel-ship`, `team-build`.
  - `partials/test-cases-resolve.md`: how a consumer finds and filters approved TCs; injected
    into `plan`, the three platform test skills, `build` / `parallel-build` / `team-build`, `eval` (and the `eval-judge` spawn template, since the judge is a cold agent). The three test skills also inject `planning-resolve`, so a standalone `/fe-test` finds its own feature.
  - `/define` chain becomes interview, spec, test-cases, plan.
  - Slug resolved once in Phase 0 and passed down to every skill and agent.
  - Routing (rule + hook), README, CHANGELOG, version bump.
- **Out of scope:**
  - Jira and any other MCP source (next release; the partial is written source-agnostic so
    adding one is a table row).
  - Push / webhooks, scheduled polling.
  - A craftkit MCP server, or distributing MCP server config through `sync.sh`.
  - Writing to Figma (comments included).
  - Lark bitable publish and QA-feedback import (v1.47, after the T0 spike proves markers
    stable; the bitable decision and re-read guard below stand for that release).
  - Lark Sheets publish (needs Open API outside MCP).
  - Lark as master copy or approval source.
  - Generating or regenerating TCs from the diff or the code.
- **Constraints:**
  - Content-only repo, bash 3.2; the host is the MCP client, and tool names differ per host,
    so skills name capabilities ("a Figma file-read tool"), never concrete tool ids.
  - IT-sanctioned MCP servers and company accounts only; the skills must say so.
  - Drift check is marker-agnostic: use a native revision / version field when the source
    exposes one, else a content hash of the fetched section. Per source, from
    `docs/research/lark-figma-mcp-revisions.md`:

    | Source | Marker | Reachable via |
    |---|---|---|
    | Lark docx | `revision_id` (`docx.v1.document.get`) | local Lark MCP, only if that tool is enabled with `-t` (not in any preset) |
    | Lark, many docs | `latest_modify_time` (`drive.v1.meta.batchQuery`, 200/call) | local Lark MCP, `-t` |
    | Lark hosted MCP, or tools not enabled | content hash of the fetched doc | any Lark read tool |
    | Figma node | content hash of the MCP node read | Figma MCP (no MCP tool returns `version`) |
    | Figma file | `version` from REST `GET /v1/files/:key/meta` | REST only, optional, needs a company token |

  - Lark MCP has no Sheets v2 tools, so the published Lark TC view is a **bitable** (one record
    per TC), written and read through the MCP default preset. Excel covers the spreadsheet file
    need. Lark Sheets via the Open API is deferred.
  - No em-dash, README sync matrix, CHANGELOG + version bump, `check.sh` exit 0.
- **Key decisions:**
  - Repo is the master copy for TCs; Lark and Excel are published views.
  - Approval is dev-owned in the repo (`status` edited by a human, as with intent `status`).
  - TCs live in a sibling `docs/planning/<slug>.tests.md`, keyed by the same slug. It carries
    `feature: <slug>` and **no line starting with `status:`** (TCs are a table, so a per-TC
    status is never at column 0), and `planning-resolve` globs exclude `*.tests.md` as a second
    guard, else every feature would resolve as two active candidates.
  - Per TC: `id` (TC-001), `title`, `steps`, `expected`, `source` (pointer + section), `status`
    (`draft` / `approved` / `rejected` / `needs-review`), `automation`
    (`jest` / `junit` / `quick` / `manual`). A TC with no source is marked `inferred`.
  - Freshness markers are pointers plus a marker, never cached content (ADR-0002 extended to
    external sources). Weighty enough for an `/adr` after build.
  - Isolation by construction: fetch only pointers in the resolved slug's `sources:`; no free
    search. One git worktree per concurrent feature is recommended, not enforced.
- **Risks & open questions:**
  - No conditional write exists: docx `document_revision_id` is a version selector, not a
    documented precondition, and bitable writes take no revision at all (research note §2). The
    publish guard is therefore read-compare-write with a residual race; the skill states it.
  - Content-hash stability: a Figma MCP read that returns generated code, not structure, may
    vary run to run and report false drift. Hash the structural read (node metadata), and
    verify stability before relying on it.
  - Bitable drift for QA feedback relies on record `last_modified_time` (needs
    `automatic_fields=true`) or a content hash; whether record edits bump the app `revision` is
    not determinable (research note §2.3), so the app revision is not used.
  - Routing collision: "test cases" vs "write tests". Needs a tiebreaker: TC *documents*
    (title/steps/expected, QA, Lark, Excel) go to `/test-cases`; test *code* goes to the
    platform test skill.
  - Token cost: a 50-TC file injected whole floods context; consumers read only the TC ids
    their task maps to.
- **Acceptance:**
  - Given a `sources:` entry whose marker differs from the live one, when any context skill
    runs, then it prints `drifted` for that source and proposes `needs-review` for citing TCs.
  - Given no MCP server connected, when `/fe-context` runs, then output equals today's plus one
    `cannot-verify` line per source.
  - Given approved and draft TCs, when `/plan` runs, then every task row cites approved TC ids
    only and drafts are listed as unverified.
  - Given approved TC-003 with `automation: jest`, when `/fe-test` runs, then exactly one test
    titled with `TC-003` exists.
  - Given a source marker that differs between two reads of an unchanged source, when T0 runs,
    then that marker kind is dropped to `cannot-verify` in `external-sources.md`.
  - Given `mcp-a.md` and `mcp-b.md` both active, when a skill runs for `mcp-a`, then it reads no
    pointer or TC from `mcp-b`.
  - `bash check.sh` exits 0; `bash sync.sh` twice, second run all `(up to date)`.

## Task Plan
**Updated:** 2026-09-24T00:00:00Z · **By:** /plan

| ID | Task | Acceptance | Depends on | Executes via |
|----|------|-----------|-----------|--------------|
| T0 | Spike: read one real Figma node (remote + desktop MCP) and one real Lark doc twice each, on two hosts; pipe output through a fixed normalizer + `shasum`. Record results in the research note | Identical hashes per source, or that marker kind is marked `cannot-verify` for v1; normalizer command pinned | none | manual, with company MCP access (dev runs it) |
| T1 | `partials/planning-resolve.md`: glob excludes `*.tests.md`; document `sources:` frontmatter (pointer + `seen`) and the sibling `<slug>.tests.md`; resolve once in Phase 0, pass slug down | Fixture with `a.md` (active) + `a.tests.md` resolves exactly one candidate | none | direct authoring |
| T2 | `partials/external-sources.md`: capability-named reads, per-source marker table as settled by T0, clean / drifted / cannot-verify, fetch only the passed slug's `sources:`, markers once per workflow and content only on drift, skip when no slug passed, IT-sanctioned servers only, never cache content, `seen` written only by `/spec` and `/test-cases` | Exists; no em-dash; no concrete `mcp__` id; states skip-without-slug and cannot-verify fallback | T0 | direct authoring |
| T3 | `partials/test-cases-resolve.md`: locate `<slug>.tests.md`, TC table schema (7 fields, 4 statuses, no column-0 `status:`), `approved` only as requirements, read only mapped ids, never derive from the diff | Exists; schema complete | T1 | direct authoring |
| T4 | New `skills/test-cases/SKILL.md`: generate from sources (cite or mark `inferred`), drift re-review to `needs-review` then bump `seen` on confirm, Excel via `xlsx` skill; injects T1-T3 | Name matches dir; injections render on `sync.sh`; criteria 1, 6, 8 each have a step | T1, T2, T3 | direct authoring |
| T5 | Inject `external-sources` into `fe-context`, `android-context`, `ios-context` (slug from caller, no resolver), `spec`, `plan`, `fe-design`; `/spec` template writes `sources:` with first `seen` | Hosts list it; context skills still write no file (check.sh:1449) | T2 | direct authoring |
| T6 | Inject `planning-resolve` into `build`, `parallel-build`, `parallel-review`, `parallel-ship`, `team-build`; inject `test-cases-resolve` into `plan` (task rows gain a `TCs` column), `fe-test` / `android-test` / `ios-test` (one test per automatable TC, titled with its id), `eval` (+ `TEST CASES:` in the judge template), `build` / `parallel-build` / `team-build` (test-case gate line); `planning-resolve` also into the 3 test skills for standalone runs | Every host injects its partials; build gates list missing TC ids | T1, T3 | direct authoring |
| T7 | `/define` chain: interview, spec, test-cases, plan (new gate) | `commands/define.md` has the phase and gate | T4 | direct authoring |
| T8 | Routing: rule tree + tiebreaker (TC documents to `/test-cases`, test code to platform test skill), `hooks/craftkit-routing.js` | `sync.sh` drift guard passes; hook advertises `/test-cases` | T4 | direct authoring |
| T9 | `check.sh`: (a) behavioral resolver fixture excludes `*.tests.md`; (b) extend the check-32 host list (check.sh:1422) to the 5 orchestrators; (c) context skills inject `external-sources` but not `planning-resolve`; (d) no concrete `mcp__` id in `skills/`, `commands/`, `partials/`; (e) every TC consumer injects `test-cases-resolve` | Each fails on a deliberately broken copy, then passes | T1, T2, T5, T6 | direct authoring + `bash check.sh` |
| T10 | README (skills table, tree, partials, and the Gateway / Orchestrator naming + runtime map below in the architecture section), spec `## Spec` gains the same map as a Key decision, `CHANGELOG.md` v1.46.0, version in `package.json` + README header | Version-agreement, README-coverage and anchor-link checks pass; map marks unbuilt parts | T4, T7, T8 | direct authoring |
| T11 | Full verify | `bash check.sh` exits 0; `bash sync.sh` `Sync complete.`, second run all `(up to date)` | T0-T10 | `bash check.sh`, `bash sync.sh` |

**Parallelizable now:** T0, T1
**Critical path:** T0 → T2 → T4 → T8 → T10 → T11 (6 deep)
**Spec criteria verified by `/eval` on a real feature run, not check.sh** (prose behavior): 1, 3, 4, 5, 6, 7 (isolation is by construction in T2, not mechanically checkable).
**Deferred to v1.47:** bitable publish + QA-feedback import, gated on T0.

### Runtime map (source for T10)

Names: **CraftKit Gateway** = `hooks/` (Claude only): Router (`craftkit-routing.js`,
UserPromptSubmit), Loader (`craftkit-platform-rules.js`, SessionStart), Guards (`gate-skill-first`,
`gate-read-size`, `craftkit-read-cap`, PreToolUse), Exit gates (`gate-verify-on-stop`,
`gate-announce-honored`, Stop). **Orchestrators** = `commands/*.md`. **Distributor** = `sync.sh` +
`adapters/` (install time only). Cursor, Gemini and Codex have no Gateway: they get the routing rule
text, advisory not enforced. The Gateway does not see MCP calls today; a PreToolUse Guard on Lark
write tools is the candidate confirm-enforcer for v1.47.

```
 INSTALL TIME                     RUNTIME (inside each agent host)
 sync.sh + adapters/  ──sync──►
 (Distributor)        ┌─ CRAFTKIT GATEWAY (hooks/, Claude only) ─────────────────────────────┐
                      │ Router      craftkit-routing.js         UserPromptSubmit             │
                      │ Loader      craftkit-platform-rules.js  SessionStart                 │
                      │ Guards      gate-skill-first · gate-read-size · read-cap  PreToolUse │
                      │ Exit gates  gate-verify-on-stop · gate-announce-honored  Stop        │
                      └───────────────┬──────────────────────────────────────────────────────┘
                                      ▼ routes each prompt to
            ORCHESTRATORS  commands/*.md
            /define · /parallel-build · /build · /team-build · /parallel-review · /parallel-ship · /fix · /ship
              │ Phase 0: resolve slug once (planning-resolve), approved TCs (test-cases-resolve), pass down
              ├──► SKILLS  skills/*   /spec · /test-cases* · /plan · /fe-test · /eval · context skills
              │        └──► MCP servers via the host's client: Figma · Lark   (external-sources*)
              └──► AGENTS  agents/*.md  cold reviewers (Claude only)
                                      │ read / write
            STATE (repo, per feature)  docs/planning/<slug>.md        intent + sources: pointers + seen
                                       docs/planning/<slug>.tests.md  test cases (repo is master)
            VIEWS (published)          Excel now · Lark bitable in v1.47

 * = planned, not built yet (T2, T4, T5)
```

## Decisions
_(pointers appended by /adr)_
