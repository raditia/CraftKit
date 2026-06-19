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
- `caveman` — output compression: terse, accurate, no filler (full mode by default)
- `using-agent-skills` — this file: routing, behaviors, severity labels

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

Match natural language to the right command. **Dynamic parallel is the default** — static sequential available via explicit slash command when a lightweight run is needed.

| User says | Run | Mode |
|-----------|-----|------|
| "build feature X", "create a new screen", "implement X", "I want to create X" — **object must be a feature/screen/module, not a test** | `/parallel-build` | dynamic |
| "scaffold a module", "scaffold X", "scaffold only" — **scaffold intent without full build** | `/build` | sequential |
| "help me review", "review the changes", "code review", "LGTM check", "can you check my changes?" — **feedback intent, no merge signal** | `/parallel-review` | dynamic |
| "get this ready to merge", "ship this", "prepare for PR", "is this ready?", "can I merge this?" — **merge intent present** | `/parallel-ship` | dynamic |
| "something is broken", "fix this bug", "this crashes", "why is X not working", "coverage is failing in CI" — **clear breakage signal**; vague complaints without error/crash/fail → `/parallel-review` instead | `/fix` | sequential (linear by nature) |
| Any test work: "write tests", "add tests", "update tests", "fix tests", "test this", "do tests need updating", "any tests to update", "coverage is low", "improve coverage", "I need tests for X", "create a test for X", "create tests for X", "should I update tests", "are there tests to update" — **test authoring/updating, not broken coverage**. When in doubt about test intent → default here | `/fe-test` | — |
| "generate PR message", "write PR description", "draft a PR", "what should my PR say", "PR message for this branch" | `/pr-message` | — |

**Tiebreakers:**
- Vague complaint ("this looks wrong", "something seems off") — no error/crash/fail signal → `/parallel-review`
- "scaffold" verb alone → `/build` not `/parallel-build`
- Merge intent ("ready to merge", "can I merge", "ship") → `/parallel-ship` over `/parallel-review`
- Coverage mentioned + failing/CI context → `/fix`; coverage mentioned + authoring/update context → `/fe-test`
- Any ambiguous test query ("any tests?", "tests needed?", "should tests change?") → `/fe-test`

**Sequential fallback** — use explicit slash command when you want a lightweight, single-pass run:

| Explicit command | When to prefer |
|-----------------|----------------|
| `/review` | Quick sanity check, small diff, no need for parallel agents |
| `/ship` | Simple pre-merge gate, already know tests pass |
| `/build` | Scaffold-only or parallel validation overhead not worth it |

### Individual skills (use when task is narrower than a full workflow)

```
Task arrives
  ├── Need context only? ──────────────────────────→ /fe-context
  ├── Scaffold only (existing context)? ────────────→ /fe-scaffold
  ├── EVPMR pattern review only? ──────────────────→ /fe-review
  ├── Designing component / hook structure? ────────→ /fe-patterns
  ├── Performance bottleneck (waterfall, bundle)? ──→ /fe-performance
  ├── Accessibility (labels, roles, focus, a11y)? ──→ /fe-a11y
  ├── Writing or improving tests only? ────────────→ /fe-test
  ├── Review or simplify code quality? ────────────→ /code-quality
  ├── Debug a bug (reproduce → isolate → fix)? ─────→ /debug
  ├── Over-engineering audit on a diff/file? ───────→ /ponytail-review
  ├── Whole-repo bloat scan? ───────────────────────→ /ponytail-audit
  └── List all deliberate shortcuts (ponytail:)? ───→ /ponytail-debt
```

---

## Parallel workflow: dynamic classifier

Used by `/parallel-review`, `/parallel-ship`, `/parallel-build`. Run this classification step before spawning any Phase 2 agents.

### Step 1 — Read the diff and actual changed files

```bash
rtk git diff <base>...HEAD --name-only   # file list
rtk git diff <base>...HEAD               # full diff
```

For each changed file, read enough of its actual content to confirm what layer it belongs to — don't rely on filename alone.

### Step 2 — Classify and select agents

| Changed file pattern | Agent(s) to add |
|---------------------|-----------------|
| `View*.tsx` | `fe-review`, `fe-a11y` |
| `Presenter*.ts` | `fe-review`, `code-quality` |
| `Model*.ts` | `code-quality` |
| `Entry*.tsx` | `fe-review` |
| `Resource*.ts` | `fe-review` |
| `auth/*`, `payment/*`, `*credential*`, `*token*` | `code-quality` (security emphasis — note in prompt) |
| `package.json` changed | `code-quality` (dependency audit — note in prompt) |
| Test files only (all changed files match `__tests__/*` or `*.test.*`) | **Skip Phase 2** — fast gates only |

Dedup the set. Always include `code-quality` if any non-test, non-resource code changed.

### Step 3 — Flag conditions

Evaluate before spawning:

| Condition | Action |
|-----------|--------|
| Diff > 300 lines | Add `[WARNING] Change size: N lines — consider splitting` to synthesis |
| 3+ EVPMR layers changed | Add adversarial agent: "argue strongest case against merging this" |
| Security-sensitive paths | Emphasize security axis in `code-quality` agent prompt |

### Step 4 — Announce selection

Before spawning agents, tell the user:
```
Classifier selected: [agent-a, agent-b, agent-c] based on: View*.tsx + Presenter*.ts changed
Spawning N agents in parallel...
```

---

## Standard context loading

Every skill follows this on start — not repeated per skill:
1. Find project root — nearest `package.json` going up from CWD
2. Freshness check — run both in parallel:
   ```bash
   rtk git branch --show-current
   rtk git rev-parse HEAD
   ```
   Then read the `**Branch:**` and `**Commit:**` fields from the `docs/context.md` header (first 5 lines).
   - If `docs/context.md` missing → run `/fe-context`, then continue
   - If branch mismatch OR commit mismatch → regenerate with `/fe-context`, then continue
   - If both match → context is fresh, proceed
3. **Always read `docs/context.md`** — mandatory, not optional. Read only the sections the skill specifies (see each skill's **Context:** line); at minimum: Summary + Key Changes
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

Both must be clean. Common type misses: spread arg types (TS2556), missing required props (TS2322), incompatible types in mocks.

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
Running /fe-test [everyday: claude-sonnet-4-6] — write and verify tests for changed code paths.
Running /pr-message [cheapest: claude-haiku-4-5] — generate PR message from branch diff.
Running /fe-context [cheapest: claude-haiku-4-5] — generate context doc from staged changes.
```
One line, before the skill executes. Lets the user redirect before work begins. Read the skill's `**Model:**` line to get the right label — use `cheapest`, `everyday`, or `escalated` as the tier label.

---

## Skill authoring rules

Apply these checks every time a skill, rule, or command is **added or updated** in this repo. Non-negotiable — same weight as the core operating behaviors.

### 1. Conflict check (before writing anything)

Scan all files in `rules/`, `skills/`, and `commands/` for:

| Check | How |
|-------|-----|
| Duplicate concept | Same pattern, constraint, or checklist item already defined elsewhere |
| Duplicate command | Same slash command or trigger phrase registered in multiple files |
| Contradicting rule | Two files prescribe opposite behavior for the same situation |
| Redundant section | Content that already lives in an always-active rule and doesn't need repeating |

If a conflict is found: surface it explicitly before proceeding. Do not silently merge or overwrite.

```
CONFLICT: [description]
Existing: [file:section]
Proposed: [new content]
Resolution: A) extend existing  B) replace  C) both are needed — why?
→ Which?
```

### 2. Token audit (before finalizing any file)

Every token in a skill file must earn its place. Run this check before saving:

| Signal | Action |
|--------|--------|
| Section already covered by an always-active rule | Remove — rules are always in context |
| Prose that could be a table or bullet | Convert |
| Code example longer than needed to illustrate the point | Trim to the minimal illustrative case |
| Repeated boilerplate across multiple skills | Move once to `using-agent-skills` or a rule; reference from skills |
| Step restating what another skill already does | Replace with "run `/skill-name`" |

Target: every line either teaches something unique or provides a reference a reader couldn't infer from elsewhere. If removing a line loses no information, remove it.

### 3. README update (after every add/update/remove)

`README.md` must stay in sync with the repo state. Update immediately — not as an afterthought.

| Change | README update required |
|--------|----------------------|
| New skill added | Add row to the correct skills table with skill name, when to use, escalate-if |
| Skill removed | Remove its row |
| Skill renamed | Update name in table and any cross-references in commands |
| New rule added | Add row to the Rules table |
| New command added | Add row to the Orchestrators table |
| Skill discovery tree changed | Update the tree in `using-agent-skills.md` AND README |
| Version bumped | Update `# craftkit \`vX.Y.Z\`` header AND add changelog row — GH Action auto-creates the release on push |

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
9. Skipping `docs/context.md` read — mandatory at skill start, no exceptions
10. Context flooding — loading entire files not relevant to the current task
11. **Skipping skill classification before responding** — always check skills first; always announce match or no-match; never silently bypass this gate

---

## Model routing

Use the everyday model by default. Escalate inline when you detect genuine uncertainty — not as a reflex. For decisions where being confidently wrong is expensive, use the fusion panel instead of a single escalation.

| AI | Everyday | Escalate | Fusion panel |
|---|---|---|---|
| Claude Code | `claude-sonnet-4-6` | `claude-opus-4-8` | 2× `claude-opus-4-8` → opus judge |
| Gemini CLI | `gemini-2.5-flash` | `gemini-2.5-pro` | — |
| Cursor | claude-sonnet / gpt-4o | claude-opus / o1 | — |
| Copilot | `claude-sonnet-4-6` | `claude-opus-4-8` | — |

### Escalation triggers → single opus
- Architecture decision with significant, non-obvious tradeoffs
- Security-sensitive code with unclear threat model
- Debugging with no clear hypothesis after 2 isolation attempts
- Refactor touching > 5 interdependent files with complex type constraints

### Fusion panel triggers → 2× opus → opus judge
Use when a single higher-model pass might still miss something and being wrong has real cost:
- Irreversible production changes (schema migrations, data transforms, permanent deletes)
- Security architecture with meaningful attack surface and unclear threat model
- Complex tradeoff where multiple independent reasoning paths are likely to diverge

### Escalation process (single opus)

Do NOT ask the user to switch models. Escalate inline:

1. **Inform the user** — one line, before escalating:
   ```
   Low confidence on [specific problem] — consulting higher model.
   ```
2. **Spawn a higher-model agent** with the specific question or task (not the whole skill — isolate the uncertain part)
3. **Incorporate the result** and continue on the everyday model
4. **Note what was consulted** at the end of your response:
   ```
   [consulted claude-opus-4-8 for: architecture tradeoff on X]
   ```

Escalation is for a targeted question, not a full hand-off. Stay in control; use the higher model as a specialist you consult for one decision.

### Fusion panel process

Adopted from the independence-then-synthesis principle: same prompt → multiple independent runs → judge synthesizes. Two independent models diverge on reasoning paths, tool calls, and edge cases — synthesis of those divergences beats one model run once.

1. **Inform the user** — one line:
   ```
   High-stakes decision on [X] — routing to fusion panel (2× opus).
   ```
2. Write the question **verbatim** — no lenses, no personas assigned. Every panelist gets the task straight.
3. **Spawn 2 independent `claude-opus-4-8` agents** in a single message (so they run concurrently). Same prompt, no cross-contamination.
4. **Classify the deliverable**, then synthesize:
   - **Artifact (code, config, script)** → Track A: run both candidates, merge by what demonstrably works, verify. The seam between grafted pieces is where merges silently break — run the merged result and fix until it passes.
   - **Research / analysis** → Track B: five sections — **Consensus** (independent agreement = highest confidence), **Contradictions** (state both positions and adjudicate — never bury a conflict), **Partial coverage** (depth only some panelists engaged), **Unique insights** (non-obvious points from one panelist — highest-leverage payoff), **Blind spots** (what the panel as a whole missed — you as judge may add one none of them named).
5. Write the final answer grounded in the synthesis. It must follow from the analysis, not be one panelist's answer lightly edited.
6. **Note at end of response:**
   ```
   [consulted fusion panel (2× claude-opus-4-8) for: X]
   ```

Evidence over assertion: a panelist that ran the code or read a primary source outranks one reasoning from memory.
