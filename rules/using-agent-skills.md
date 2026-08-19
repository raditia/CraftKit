---
name: using-agent-skills
description: Skill routing, model selection, core operating behaviors, and failure modes. Always active.
---

**Commands:** always prefix with `rtk` — `rtk git status`, `rtk git diff`, `rtk tsc`, `rtk lint`
**Tests:** run from workspace root — `rtk test --testPathPattern=<path-or-pattern> --no-coverage` (or `--coverage` for gate checks)

---

# Using Agent Skills

## Always active (no invocation needed)

Loaded from `rules/` automatically on every session:
- `karpathy-guidelines` — think before coding, simplicity, surgical changes, goal-driven
- `fe-rules` — EVPMR layer constraints, TypeScript, styling, React correctness, tracking
- `using-agent-skills` — this file: routing, behaviors, severity labels

Output compression (caveman) is delivered by the caveman plugin's hooks, not a synced rule — one channel, no duplicate.

---

## Skill discovery

**Intent-first routing — BLOCKING REQUIREMENT.** Before generating ANY response to a user request, classify intent against available skills. This is mandatory — not advisory. Do NOT require specific trigger words — infer from meaning, not keywords. Do NOT skip this step even for simple or conversational requests.

Classification order:
1. **Orchestrator** — does the request imply build / review / ship / fix / test / PR? → match orchestrator table below
2. **Individual skill** — narrower task (scaffold, patterns, a11y, performance, context)? → match skill tree below
3. **No match** — no skill matches → **announce this explicitly before responding**:
   ```
   No skill matched for this request. Responding directly.
   ```

Announce the matched skill before invoking it (see core behavior #11). If genuinely ambiguous between two skills, name both and ask.

### Orchestrator commands (multi-skill workflows — use these first)

Match natural language to the right command. **Dynamic parallel is the default where you can spawn subagents** — if you can't, swap in the sequential twin per the no-spawn table below and carry on. Static sequential is also available by explicit slash command for a lightweight run.

| User says | Run | Mode |
|-----------|-----|------|
| "plan this feature", "define feature X", "spec and plan X", "let's plan before building", "help me scope this out" — **planning intent before build; ask/scope/approach not yet clear** | `/define` | sequential (checkpoint-gated) |
| "build feature X", "create a new screen", "implement X", "I want to create X" — **object must be a feature/screen/module, not a test** | `/parallel-build` | dynamic |
| "scaffold a module", "scaffold X", "scaffold only" — **scaffold intent without full build** | `/build` | sequential |
| "help me review", "review the changes", "code review", "LGTM check", "can you check my changes?" — **feedback intent, no merge signal** | `/parallel-review` | dynamic |
| "get this ready to merge", "ship this", "prepare for PR", "is this ready?", "can I merge this?" — **merge intent present** | `/parallel-ship` | dynamic |
| "something is broken", "fix this bug", "this crashes", "why is X not working", "coverage is failing in CI" — **clear breakage signal**; vague complaints without error/crash/fail → `/parallel-review` instead | `/fix` | sequential (linear by nature) |
| Any test work: "write tests", "add tests", "update tests", "fix tests", "test this", "do tests need updating", "any tests to update", "coverage is low", "improve coverage", "I need tests for X", "create a test for X", "create tests for X", "should I update tests", "are there tests to update" — **test authoring/updating, not broken coverage**. When in doubt about test intent → default here | platform's test skill: `/fe-test` (RN/web) · `/android-test` · `/ios-test` | — |
| "generate PR message", "write PR description", "draft a PR", "what should my PR say", "PR message for this branch" | `/pr-message` | — |

**Tiebreakers:**
- Vague complaint ("this looks wrong", "something seems off") — no error/crash/fail signal → `/parallel-review`
- "scaffold" verb alone → `/build` not `/parallel-build`
- "plan"/"spec"/"define"/"scope" intent (before code exists) → `/define`; "build"/"implement" intent → `/parallel-build`. Planning verb wins only when no build-now signal.
- Merge intent ("ready to merge", "can I merge", "ship") → `/parallel-ship` over `/parallel-review`
- Coverage mentioned + failing/CI context → `/fix`; coverage mentioned + authoring/update context → the platform's test skill
- Any ambiguous test query ("any tests?", "tests needed?", "should tests change?") → the platform's test skill
- **Test intent resolves platform first.** `/fe-test` is RN/web only (jest, 93% bar, EVPMR paths) — on `*.kt`/`*.java` run `/android-test`, on `*.swift`/`*.m` run `/ios-test`. Detect from the changed files, or from the project root when nothing is changed yet. Announcing `/fe-test` on a native repo is a routing error, not a near-miss.
- "grill"/"stress-test"/"poke holes"/"challenge" an **existing** plan or decision → `/grill` (interactive rounds); no plan exists yet → `/interview`; "roast this plan doc" single-pass → `plan-roaster` agent

**No-spawn contexts — take the sequential twin, silently.** A `parallel-*` command's whole job is spawning agents, so a context that cannot spawn them cannot run one. You are in such a context when you are yourself a subagent (subagents get no Agent tool) or when a session instruction disables agent spawning. Substitute and proceed:

| Intent routes to | You cannot spawn → run |
|------------------|------------------------|
| `/parallel-build` | `/build` |
| `/parallel-review` | `/review` |
| `/parallel-ship` | `/ship` |
| `/team-build` | `/build` |

Announce the command you actually ran (`Running /build …`), not the one you couldn't. State the substitution **once** if it changes what the user gets — a skipped validation axis is a coverage gap and belongs in the output per Step 5. Re-explaining the constraint every turn is noise the user pays for; the routing table already sanctions the swap, so there is no conflict left to surface. This is not the `[WARNING] agent skipped` case, which is an agent that was spawned and died.

**Sequential fallback by choice** — same three commands, when spawning is available but not worth it:

| Explicit command | When to prefer |
|-----------------|----------------|
| `/review` | Quick sanity check, small diff, no need for parallel agents |
| `/ship` | Simple pre-merge gate, already know tests pass |
| `/build` | Scaffold-only or parallel validation overhead not worth it |

**Experimental escalation** — explicit invocation only, never auto-routed ("build feature X" still → `/parallel-build`):

| Explicit command | When to prefer |
|-----------------|----------------|
| `/team-build` | Agent-teams build: this session leads (escalated model), everyday-model teammates implement in parallel via shared task list + direct teammate messaging. All platforms. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; ~5× token cost of a solo build |

### Individual skills (use when task is narrower than a full workflow)

**Platform first.** Classify the codebase before the task: React Native / web (EVPMR, `*.tsx`, `package.json`) → `fe-*`. Native Android (`*.kt/*.java`, Gradle, MVP) → `android-*`. Native iOS (`*.swift/*.m`, `Modules/`, MVVM-C) → `ios-*`. Native mobile does **not** use EVPMR or `docs/context.md` for single-screen work — read a real sibling instead.

```
Frontend (React Native / web — EVPMR)
  ├── Need context only? ──────────────────────────→ /fe-context
  ├── Scaffold only (existing context)? ────────────→ /fe-scaffold
  ├── EVPMR pattern review only? ──────────────────→ /fe-review
  ├── Designing component / hook structure? ────────→ /fe-patterns
  ├── Performance bottleneck (waterfall, bundle)? ──→ /fe-performance
  ├── Accessibility (labels, roles, focus, a11y)? ──→ /fe-a11y
  ├── Writing or improving tests only? ────────────→ /fe-test
  ├── Review or simplify code quality? ────────────→ /code-quality
  ├── Debug a bug (reproduce → isolate → fix)? ─────→ /debug
  ├── Open-ended design/naming/fuzzy debug — need OPTIONS? → /ideate
  ├── Complex system / architecture / non-obvious downstream effects? → /think
  ├── Over-engineering audit on a diff/file? ───────→ /ponytail-review
  ├── Whole-repo bloat scan? ───────────────────────→ /ponytail-audit
  └── List all deliberate shortcuts (ponytail:)? ───→ /ponytail-debt

Planning & docs (general, opt-in — never auto-run; feed docs/context.md before execution)
  ├── Ask underspecified — de-fuzz before building? → /interview
  ├── Widen the approach — need OPTIONS? ───────────→ /ideate
  ├── Write a PRD / spec before coding? ────────────→ /spec
  ├── Break a spec into ordered verifiable tasks? ──→ /plan  (then plan-roaster agent to stress-test)
  ├── Record WHY a decision was made? ──────────────→ /adr
  ├── Stress-test an EXISTING plan/decision — interactive? → /grill  (frontier rounds; cold single-pass doc roast → plan-roaster agent)
  └── Document a feature for engineers + stakeholders? → /docs  (dual-audience, humanized)
  Chain them: /define runs interview → spec → plan checkpoint-gated (one invoke). adr + docs offered as tail of /parallel-ship.
  Full arc: /define (interview→spec→plan) → /parallel-build → /parallel-ship (→ offers /adr + /docs)

General utilities (any platform)
  ├── Research a question against primary sources? ──→ /research  (background agent, cited note in repo)
  └── Hand this session off to a fresh agent? ───────→ /handoff  (compact state + decisions + next steps)

Native Android (MVP + Core framework)          Native iOS (MVVM-C)
  ├── Architecture / how a screen works? → /android-patterns    /ios-patterns
  ├── Scaffold a new screen? ──────────→ /android-scaffold   /ios-scaffold
  ├── Review a diff? ──────────────────→ /android-review     /ios-review
  ├── Accessibility (TalkBack/VoiceOver)? → /android-a11y     /ios-a11y
  ├── Performance (jank, memory, lists)? → /android-performance /ios-performance
  ├── Write/improve unit tests? ───────→ /android-test       /ios-test
  └── Branch context (multi-screen)? ──→ /android-context    /ios-context
```

All orchestrators are platform-routed — `/build` `/fix` `/ship` `/pr-message` and the three `/parallel-*` commands detect the platform at Step 0 and dispatch to the matching `{fe,android,ios}-*` skills and agents. Same command names on every platform; only the gates and agent set change.

---

## Parallel workflow: dynamic classifier

Used by `/parallel-review`, `/parallel-ship`, `/parallel-build`. Run this classification step before spawning any Phase 2 agents.

### Step 1 — Read the diff and actual changed files

```bash
rtk git diff <base>...HEAD --name-only   # file list
rtk git diff <base>...HEAD               # full diff
```

For each changed file, read enough of its actual content to confirm what layer it belongs to — don't rely on filename alone.

### Step 1.5 — Detect platform

The routing hook already injects `Platform (detected from cwd)` each turn — take it and skip this step. The table below is for when it is absent (non-Claude tool, no marker found) or when the diff is genuinely mixed, in which case run both tables and union the sets:

| Signal | Platform | Architecture |
|--------|----------|--------------|
| `*.tsx`/`*.ts` + `package.json` | React Native / web | EVPMR |
| `*.kt`/`*.java` + Gradle | Android | MVP + Core framework |
| `*.swift`/`*.m` + `Modules/` | iOS | MVVM-C |

`code-quality`, `ponytail-review`, and `adversarial` are platform-agnostic — they apply on all three. Only the review/a11y/performance agents are platform-specific.

### Step 2 — Classify and select agents

**React Native / web (EVPMR)**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `View*.tsx` | `fe-review`, `fe-a11y` |
| `Presenter*.ts` | `fe-review`, `code-quality` |
| `Model*.ts` | `code-quality` |
| `Entry*.tsx` | `fe-review` |
| `Resource*.ts` | `fe-review` |
| `package.json` changed | `code-quality` (dependency audit — note in prompt) |
| Test files only (all match `__tests__/*` or `*.test.*`) | **Skip Phase 2** — fast gates only |

**Android (MVP + Core framework)**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `*Activity.kt`, `*Fragment.kt`, `*Widget.kt`, `res/layout/*.xml`, `@Composable` | `android-review`, `android-a11y` |
| `*Presenter.kt` | `android-review`, `code-quality` |
| `*ViewModel.kt`, `*NavigationModel.kt` | `android-review`, `code-quality` |
| `*Repository.kt`, `*Interactor.kt`, `*UseCase.kt` | `code-quality` |
| `*Module.kt`, `*Component.kt`, `*ComponentBuilder.kt` (Dagger) | `android-review` |
| `res/values*/strings.xml` | `android-review` |
| `*.gradle` / `*.gradle.kts` changed | `code-quality` (dependency audit — note in prompt) |
| Test files only (all match `src/test/**` or `*Test.kt`) | **Skip Phase 2** — fast gates only |

**iOS (MVVM-C)**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `*ViewController.swift`, `*View.swift`, `*Cell.swift` | `ios-review`, `ios-a11y` |
| `*ViewModel.swift` | `ios-review`, `code-quality` |
| `*Fetcher.swift` | `code-quality`, `ios-performance` |
| `*Contract.swift`, `*Factory.swift`, `*Coordinator.swift` | `ios-review` |
| `*.strings`, `Localizable*` | `ios-review` |
| `Podfile`, `Package.swift`, `BUILD`/`*.bzl` changed | `code-quality` (dependency audit — note in prompt) |
| Test files only (all match `*Test.swift` or `*Spec.swift`) | **Skip Phase 2** — fast gates only |

**All platforms**

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `auth/*`, `payment/*`, `*credential*`, `*token*` | `code-quality` (security emphasis — note in prompt) |

Dedup the set. Always include `code-quality` if any non-test, non-resource code changed.

> `parallel-build` and `parallel-ship` additionally include `ponytail-review` (over-engineering axis) for any non-test, non-resource change — defined in those command files, not this base table (see extensions note below). It overlaps `code-quality` only on `delete:`/dead-code; a same-`file:line` hit becomes `[CONSENSUS]` in synthesis, which is the dedup, not waste.

> **Command-specific extensions:** `parallel-build` and `parallel-ship` add agents beyond these base tables (e.g. `fe-patterns`, `fe-performance`, `android-performance`, `ios-performance`). Those additions are defined in the command file itself, not here — these tables are the shared base.

### Step 3 — Flag conditions

Evaluate before spawning:

| Condition | Action |
|-----------|--------|
| Diff > 300 lines | Add `[WARNING] Change size: N lines — consider splitting` to synthesis |
| 3+ architecture layers changed — EVPMR (Entry/View/Presenter/Model/Resource), Android MVP (View/Presenter/ViewModel/Repository/DI), or iOS MVVM-C (ViewController/View/ViewModel/Fetcher/Coordinator) | Add `adversarial` agent (definition in `agents/adversarial.md`) |
| Security-sensitive paths | Pass "Security-sensitive code present — emphasize security axis." in user message to `code-quality` agent |
| `docs/context.md` has a PLANNING block | Pass "Spec conformance: verify the diff implements the PLANNING block's spec and acceptance criteria — flag drift between what was planned and what was built." in user message to `code-quality` agent |

### Step 4 — Announce selection

Before spawning agents, tell the user — name the detected platform, since it picked the agent set:
```
Platform: Android (MVP)
Classifier selected: [android-review, android-a11y, code-quality] based on: *Fragment.kt + *Presenter.kt changed
Spawning N agents in parallel...
```

### Step 5 — Handle agent failures (graceful degrade)

An agent can die before producing findings — model-key 401, rate limit, or other infra error returns no result. This is **not** a clean review: a skipped agent is missing coverage, not absence of findings. Never let a dead agent pass silently as if its axis were clean.

For every selected agent that did not return findings:

1. **Surface it** in synthesis as `[WARNING] <agent> skipped: <reason> — coverage gap on <axis>`.
2. **List it as skipped** in the `Agents:` line, not as ran.
3. **Gate the verdict** — if a review/build agent (not a fast Bash gate) was skipped by infra, the verdict is `INCOMPLETE`, never `READY TO MERGE` / `DONE`. State which axis is unverified so the user can re-run or accept the gap.

Do not retry a dead model spawn inline — the model key won't change mid-turn. Report, and if the failing agent has a `model:` override that differs from peers (e.g. `haiku` vs `sonnet`), name that override as the likely cause.

---

## Standard context loading

**Scope: RN/web skills, and native skills only on multi-screen branches.** A native single-screen task has no `docs/context.md` by design — the ten `{android,ios}-*` skills say so in their own **Context:** line, and that wins. There, the baseline is a real sibling screen read from the same module; skip this procedure entirely rather than generating a doc to satisfy it.

Where it does apply, every skill follows this on start — not repeated per skill:
1. Find project root — nearest `package.json` (RN/web), `settings.gradle` (Android), or `*.xcodeproj`/`Package.swift` (iOS) going up from CWD
2. Freshness check — run both in parallel:
   ```bash
   rtk git branch --show-current
   rtk git rev-parse HEAD
   ```
   Then read the `**Branch:**` and `**Commit:**` fields from the `docs/context.md` header (first 5 lines). The generator is the platform's context skill — `/fe-context`, `/android-context`, or `/ios-context`.
   - If `docs/context.md` missing → run that skill, then continue
   - If branch mismatch OR commit mismatch → regenerate with that skill, then continue
   - If both match → context is fresh, proceed
3. **Read `docs/context.md`** — required wherever this procedure applies. Read only the sections the skill specifies (see each skill's **Context:** line); at minimum: Summary + Key Changes
4. If context conflicts with code → `CONFUSION: docs/context.md says X but code shows Y. Options: A) ... B) ... → Which?`

---

## Severity labels

One system used across all skills and commands:

| Label | Required | Meaning |
|-------|----------|---------|
| `[ERROR]` | Yes | Must fix — blocks merge, correctness, security, or hard EVPMR violation |
| `[WARNING]` | Should | Convention deviation, soft pattern violation, or test gap |
| `[SUGGESTION]` | Optional | Improvement worth considering — author may ignore |

---

## Core operating behaviors

These apply at all times, across every skill. Non-negotiable.

### 1. Surface assumptions
Before implementing anything non-trivial, state assumptions explicitly:
```
ASSUMPTIONS I'M MAKING:
1. [requirement assumption]
2. [architecture assumption]
→ Correct me now or I'll proceed with these.
```

### 2. Manage confusion actively
When encountering inconsistencies, conflicting requirements, or unclear specs:
1. **STOP.** Do not proceed with a guess.
2. Name the specific confusion.
3. Present the tradeoff or ask the clarifying question.
4. Wait for resolution.

```
CONFUSION: spec says X but existing code shows Y.
Options: A) follow spec  B) follow code  → Which takes precedence?
```

### 3. Push back when warranted
- Point out the issue directly
- Quantify the downside where possible ("this adds ~200ms latency" not "might be slower")
- Propose an alternative
- Accept the human's decision once they have full information

### 4. Enforce simplicity
Before finishing any implementation:
- Can this be done in fewer lines?
- Are these abstractions earning their complexity?
- Would a senior engineer say "why didn't you just…"?

### 5. Maintain scope discipline (surgical changes)
Touch only what was asked. When your changes create orphans — remove imports, variables, and functions that **your** changes made unused. Do NOT remove pre-existing dead code unless explicitly asked.

### 6. Verify before claiming done
Every skill has a verification step. "Seems right" is never sufficient — there must be evidence: passing tests, build output, lint clean, runtime data.

**After any code change**, run these CI gates before reporting done:

1. **Lint** — `rtk pnpm deplint` — catches ESLint violations that block CI
2. **Type check** — `rtk tsc --project tsconfig.json` — Jest uses babel and skips types; passing tests do not guarantee type-correctness
3. **Ponytail self-pass** — scan your own diff against the ponytail rubric (`karpathy-guidelines` rule 2); cut each hit or mark it `ponytail:`. Catching bloat here is why a later `/ponytail-review` has nothing to rewrite

All three must be clean. Common type misses: spread arg types (TS2556), missing required props (TS2322), incompatible types in mocks.

### 7. Use the model for judgment, not mechanics

Use Claude for: classification, drafting, summarization, extraction, tradeoff evaluation.

Do NOT use Claude for: deterministic transforms, string routing that regex handles, retries with fixed logic, any operation where "if code can answer, code answers."

In skill files: the classifier reads diffs and selects agents — that's judgment. Counting lines or matching filenames deterministically is mechanics; use Bash for that, not a prompt.

### 8. Surface token budget pressure

Token budgets are not advisory. When approaching context limits mid-task:
- Stop. Summarize what was done, what's verified, what's left.
- Tell the user explicitly: "Approaching context limit — summarizing before continuing."
- Do not silently overrun or skip steps to fit.

Project teams set their own per-task budgets. The rule is: **surface the breach, never hide it.**

### 9. Surface conflicts — never average them

When two patterns in the codebase contradict each other:
1. Pick one (prefer: more recent, more tested, closer to the affected code).
2. Explain the choice explicitly.
3. Flag the other pattern for cleanup — don't blend both.

```
CONFLICT: ComponentA uses Redux for this state, ComponentB uses local useState.
Picking: local useState — more recent pattern, no cross-component sharing needed.
Flag: ComponentA.tsx can be migrated to useState when touched next.
```

Applies at code level and at skill authoring level — see skill authoring rules below.

### 10. Intent-first skill routing — MANDATORY GATE

**Every user message gets classified against available skills BEFORE any response is generated.** This is a hard requirement — not a suggestion. No exceptions for simple, conversational, or "obvious" requests.

Steps:
1. Read message. Map intent → orchestrator or individual skill (see Skill discovery section).
2. Match found → announce + invoke (see #11). Do NOT respond until skill completes.
3. No match → output exactly:
   ```
   No skill matched for this request. Responding directly.
   ```
   Then respond.

**Never silently skip the classification step.** Skipping = wasting user tokens on work a skill would have done better. Every skipped skill check is a token waste the user pays for.

Ambiguous between two skills → name both, ask user which applies.

### 11. Announce skill invocation
Before invoking any skill or command, tell the user which one you're using and what model will run it:
```
Running /fe-test [everyday] — write and verify tests for changed code paths.
Running /pr-message [cheapest] — generate PR message from branch diff.
Running /fe-context [cheapest] — generate context doc from staged changes.
```
One line, before the skill executes. Lets the user redirect before work begins. Read the skill's `**Model:**` line to get the right label — use `cheapest`, `everyday`, or `escalated` as the tier label. Name the tier, not a model id; the id shifts every release and the injected tier line already carries it.

---

## Skill authoring rules

Authoring/updating craftkit content (rules, skills, commands, agents) is **repo-local** work — it only happens inside the craftkit source repo, where that repo's own `CLAUDE.md` is always loaded. The full authoring checklist (conflict check, token audit, README-sync matrix) lives there under **"Critical authoring rules"** — not duplicated into this always-on global rule. When editing craftkit source, follow that section. Everywhere else, this section is inert.

---

## Failure modes to avoid

1. Making wrong assumptions without surfacing them
2. Plowing ahead when confused — guessing instead of asking
3. Not surfacing inconsistencies you notice
4. Sycophancy ("Of course!") to approaches with clear problems
5. Overcomplicating code when a simpler path exists
6. Modifying code orthogonal to the task
7. Removing things you don't fully understand
8. Skipping verification because "it looks right"
9. Skipping the `docs/context.md` read where standard context loading applies — or, on a native single-screen task, generating one instead of reading a sibling screen
10. Context flooding — loading entire files not relevant to the current task
11. **Skipping skill classification before responding** — always check skills first; always announce match or no-match; never silently bypass this gate

---

## Model routing

Use the everyday model by default. Escalate inline when you detect genuine uncertainty — not as a reflex. For decisions where being confidently wrong is expensive, use the fusion panel instead of a single escalation.

**On Claude Code the tiers arrive per turn — never name a model id yourself.** `hooks/craftkit-routing.js` reads `~/.claude.json` every prompt and injects the resolved trio as `additionalContext` (`Model tiers (resolved from ~/.claude.json entitlements): cheapest=… everyday=… escalate=…`). That line is authoritative wherever a skill names a tier, and it is what makes a model release a no-op here: the hook derives the trio from `modelAccessCache` ∪ `additionalModelOptionsCache` — the newest entitled version of each family, ranked `haiku < sonnet < opus < fable`, top three families become cheapest / everyday / escalate. So an account without fable resolves haiku/sonnet/opus, one with it resolves sonnet/opus/fable, and a new `opus-6` displaces `opus-5` on its own. Entitlements unreadable → the line says so and carries family aliases only.

**Spawn agents with the family alias** (`haiku` · `sonnet` · `opus` · `fable`), not a versioned id: the Agent tool's `model:` accepts aliases and each tracks the newest model in its family, which is why `agents/*.md` frontmatter pins `sonnet` and stays correct across releases. Concrete ids are for showing the user.

| AI | Cheapest | Everyday | Escalate | Fusion panel |
|---|---|---|---|---|
| Claude Code | injected per turn (see above) | injected | injected | 2× escalate → same-tier judge |
| Gemini CLI | `flash-lite` | `flash` | `pro` | 2× `pro` → `pro` judge |
| Cursor | `auto` | `auto` | `cursor-agent --model` or the picker | 2× escalate → same-tier judge |
| Codex CLI | omit `model`, effort `low` | omit `model`, effort `medium` | omit `model`, effort `high` | 2× escalate → same-tier judge |

**No row names a versioned id, on any tool** — the same reason as the Claude row, reached differently per tool. Gemini CLI ships its own `auto`/`pro`/`flash`/`flash-lite` aliases that resolve against CLI constants *and* the account's preview entitlement, so they self-update on CLI upgrade (prefer these over the API's `gemini-*-latest`, which Google steers production away from and which can land on a rate-limited preview build). Codex CLI has no self-updating model id — OpenAI's undated ids pin the minor version — so leave `model` unset in `~/.codex/config.toml` and let the CLI's server-refreshed catalog pick, expressing the tier as `model_reasoning_effort` instead. Cursor's model lives in the picker or the account default chain; no committed file selects it, so the row is a best-effort note, not a setting. Sources and the retired ids this replaced: `docs/research/self-updating-model-ids.md`.

Cheapest = the floor for pure pattern-matching/extraction skills (scaffold, context, a11y, ponytail-*, debug's first pass) — on an account whose ladder starts at sonnet, that floor *is* sonnet, which is why the cold review agents pin `sonnet` rather than `haiku`.

### Escalation triggers → single escalate-tier model
- Architecture decision with significant, non-obvious tradeoffs
- Security-sensitive code with unclear threat model
- Debugging with no clear hypothesis after 2 isolation attempts
- Refactor touching > 5 interdependent files with complex type constraints

### Fusion panel triggers → 2× escalate-tier model → same-tier judge
Use when a single higher-model pass might still miss something and being wrong has real cost:
- Irreversible production changes (schema migrations, data transforms, permanent deletes)
- Security architecture with meaningful attack surface and unclear threat model
- Complex tradeoff where multiple independent reasoning paths are likely to diverge

### Escalation process (single higher model)

Never ask the user to switch models — escalate inline. (1) Tell the user one line first: `Low confidence on [problem] — consulting higher model.` (2) Spawn an agent on the tier's **Escalate** model — the alias from the injected tier line — scoped to the uncertain part only, not the whole skill. (3) Incorporate the result, continue on the everyday model. (4) Note at end: `[consulted <escalate-model> for: X]`. Targeted question, not a hand-off — you stay in control.

### Fusion panel process

Independence-then-synthesis: same prompt → 2 independent runs → judge synthesizes. Independent models diverge on reasoning/tool-calls/edge-cases; synthesizing the divergence beats one run.

1. Tell the user one line: `High-stakes decision on [X] — routing to fusion panel (2× <escalate-model>).`
2. Write the question **verbatim** — no lenses/personas; every panelist gets it straight.
3. Spawn 2 independent panelists, same prompt, no cross-contamination, both on the tier's Escalate model. Spawn mechanism per AI:
   - **Claude Code** — Agent tool, both in one message (concurrent), `model:` = the Escalate alias from the injected tier line
   - **Gemini CLI** — shell `&`-parallelism into temp files, judge call reads both
   - **Cursor** — two background agent tabs at once, both on the same escalate-tier model
   - **Codex CLI** — two `codex exec` calls backgrounded into temp files, judge call reads both
4. Classify the deliverable, then synthesize:
   - **Artifact (code/config/script)** → run both candidates, merge by what demonstrably works, verify — the graft seam is where merges silently break, so run the merged result and fix until it passes.
   - **Research/analysis** → five sections: **Consensus** (agreement = highest confidence) · **Contradictions** (state both, adjudicate — never bury) · **Partial coverage** (depth only some engaged) · **Unique insights** (one panelist's non-obvious point — highest leverage) · **Blind spots** (what the whole panel missed; add one they didn't name).
5. Final answer follows from the synthesis, not one panelist lightly edited.
6. Note at end: `[consulted fusion panel (2× <escalate-model>) for: X]`.

Evidence over assertion: a panelist that ran the code / read a primary source outranks one reasoning from memory.
