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

### Orchestrator commands (multi-skill workflows — use these first)

Match natural language to the right command:

| User says | Run |
|-----------|-----|
| "build feature X", "create a new screen", "implement X", "scaffold a module" | `/build` |
| "help me review", "review the changes", "code review", "LGTM check" | `/review` |
| "something is broken", "fix this bug", "this crashes", "why is X not working" | `/fix` |
| "get this ready to merge", "ship this", "prepare for PR", "is this ready?" | `/ship` |
| "write tests", "add tests", "test this", "coverage is low", "improve coverage", "I need tests for X" | `/fe-test` |

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
  └── Review or simplify code quality? ────────────→ /code-quality
```

---

## Standard context loading

Every skill follows this on start — not repeated per skill:
1. Find project root — nearest `package.json` going up from CWD
2. If `docs/context.md` missing → run `/fe-context` first
3. Read only the sections the skill specifies (see each skill's **Context:** line)
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

**After any TypeScript code change** (source or test), run `npx tsc --noEmit` filtered to changed files before reporting done. Jest uses babel and skips type checking — passing tests do not guarantee type-correctness. Common misses: spread arg types (TS2556), missing required props (TS2322), incompatible types in mocks.

### 7. Announce skill invocation
Before invoking any skill or command, tell the user which one you're using:
```
Running /fe-test — write and verify tests for changed code paths.
```
One line, before the skill executes. Lets the user redirect before work begins.

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
9. Context starvation — acting without loading `docs/context.md`
10. Context flooding — loading entire files not relevant to the current task

---

## Model routing

Use the everyday model by default. Escalate inline when you detect genuine uncertainty — not as a reflex.

| AI | Everyday | Escalate to |
|---|---|---|
| Claude Code | `claude-sonnet-4-6` | `claude-opus-4-7` |
| Gemini CLI | `gemini-2.5-flash` | `gemini-2.5-pro` |
| Cursor | claude-sonnet / gpt-4o | claude-opus / o1 |
| Copilot | `claude-sonnet-4-6` | `claude-opus-4-7` |

### Escalation triggers
- Architecture decision with significant, non-obvious tradeoffs
- Security-sensitive code with unclear threat model
- Debugging with no clear hypothesis after 2 isolation attempts
- Refactor touching > 5 interdependent files with complex type constraints

### Escalation process

Do NOT ask the user to switch models. Escalate inline:

1. **Inform the user** — one line, before escalating:
   ```
   Low confidence on [specific problem] — consulting higher model.
   ```
2. **Spawn a higher-model agent** with the specific question or task (not the whole skill — isolate the uncertain part)
3. **Incorporate the result** and continue on the everyday model
4. **Note what was consulted** at the end of your response:
   ```
   [consulted claude-opus-4-7 for: architecture tradeoff on X]
   ```

Escalation is for a targeted question, not a full hand-off. Stay in control; use the higher model as a specialist you consult for one decision.
