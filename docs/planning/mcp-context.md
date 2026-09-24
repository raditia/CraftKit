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
     `cannot-verify` for that source and otherwise behaves exactly as before (git-only).
  3. `/plan` maps every task to at least one approved TC id; `/build`, `/parallel-build` treat
     only `approved` TCs as requirements and list `draft` / `needs-review` ones as unverified.
  4. Each approved TC with `automation: jest|junit|quick` gets exactly one test, named with the
     TC id, in `/fe-test`, `/android-test`, `/ios-test`; `manual` TCs are listed, not tested.
  5. `/eval` receives the approved TC set as acceptance criteria.
  6. Lark publish writes only after explicit confirm, and aborts without writing when a re-read
     just before the write shows the target changed since the draft (no server-side
     precondition exists, so the skill names the residual race).
  7. Excel export produces one `.xlsx` with id, title, steps, expected, status per TC.
  8. With two features in the repo, no skill or agent fetches a source or reads a TC file that
     belongs to the other feature's slug.
  9. `bash check.sh` exits 0, with new checks for items 2 and 8 that fail before the change.
- **In scope:**
  - `sources:` list in the intent file: Figma and Lark pointers, each with a `seen` marker.
  - `partials/external-sources.md`: read-time freshness check (clean / drifted /
    cannot-verify), scoped fetch, git-only fallback. Injected into `fe-context`,
    `android-context`, `ios-context`, `spec`, `plan`, `fe-design`, and the build orchestrators.
  - New `/test-cases` skill: generate from sources, re-review on drift, import QA feedback from
    Lark as a proposal, publish to Lark (propose, confirm, guarded write), export Excel via the
    installed `xlsx` skill.
  - `partials/test-cases-resolve.md`: how a consumer finds and filters approved TCs; injected
    into `plan`, the three platform test skills, `build` / `parallel-build`, `eval`.
  - `/define` chain becomes interview, spec, test-cases, plan.
  - Slug resolved once in Phase 0 and passed down to every skill and agent.
  - Routing (rule + hook), README, CHANGELOG, version bump.
- **Out of scope:**
  - Jira and any other MCP source (next release; the partial is written source-agnostic so
    adding one is a table row).
  - Push / webhooks, scheduled polling.
  - A craftkit MCP server, or distributing MCP server config through `sync.sh`.
  - Writing to Figma (comments included).
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
    `feature: <slug>` and **no `status:` line**, and `planning-resolve` globs exclude
    `*.tests.md`, else every feature would resolve as two active candidates.
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
  - Given the Lark doc changed after the draft, when publish is confirmed, then nothing is
    written and the user is told why.
  - Given `mcp-a.md` and `mcp-b.md` both active, when a skill runs for `mcp-a`, then it reads no
    pointer or TC from `mcp-b`.
  - `bash check.sh` exits 0; `bash sync.sh` twice, second run all `(up to date)`.

## Task Plan
_(owned by /plan)_

## Decisions
_(pointers appended by /adr)_
