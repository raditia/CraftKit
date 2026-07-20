---
name: ideate
description: Parallel divergent ideation — spawn N isolated idea generators under distinct cognitive frames, then a critic scores/clusters/deepens. Use for open-ended design, architecture, naming, or fuzzy debugging with no clear direction. Adapted from UditAkhourii/adhd (MIT).
alwaysApply: false
---

**Model:** everyday for generators — escalate the critic/deepen pass (`claude-opus-4-8`) for high-stakes decisions.
**Cost:** ~10 agent calls, 30–90s, 5–10× a direct answer. Not free — the gate below stops casual use.

> **Core behaviors:** Surface assumptions before acting. STOP and ask when confused. See `/using-agent-skills`.
> **Not the fusion panel.** Fusion panel (`using-agent-skills` → Model routing) *verifies one decision* — same prompt, 2× parallel, judge synthesizes. `/ideate` *generates options* — distinct-frame prompts, N parallel, critic scores + clusters. Verify a choice → fusion panel. Widen the choice set → `/ideate`.

---

## Pre-flight gate — all 3 must hold, else refuse and answer directly

| Check | Pass condition |
|-------|----------------|
| Explicit or open scope | User asked to brainstorm/explore/"what are the options", OR problem is genuinely open-ended |
| No single right answer | Design / architecture / naming / API shape / fuzzy debug — NOT syntax, known bugs, or lookups |
| High enough stakes | Worth 5–10× cost — a decision that's hard to reverse or shapes later work |

Any check fails → `Ideation gate not met (<which>). Answering directly.` then answer normally. Do not spawn agents.

---

## Phase 1 — Diverge (parallel, isolated)

Spawn **5 idea generators in ONE message** — parallel, never serialized. Serial execution collapses divergence into "one wider thought" and defeats the method.

Each generator receives, and **nothing else** (no peer output — isolation is the point):
- the problem statement + user context
- ONE cognitive frame (below) — pick 5 distinct frames that fit the problem
- generator-only instruction: **produce ideas, do NOT evaluate, rank, or hedge**

Each returns JSON: `[{"idea": "...", "rationale": "..."}, ...]` — 5–6 ideas each (~30 total).

### Cognitive frames — pick 5 distinct

| Frame | Vantage |
|-------|---------|
| First-principles | Ignore how it's usually done. Rebuild from the raw constraint up. |
| Constraint-inverter | What if the hardest constraint were removed — or doubled? |
| Adversary | How would someone abuse, break, or exploit this? Design from the attack backward. |
| Steal-from-adjacent | How does a *different* domain (games, biology, finance, ops) already solve this shape? |
| Radical-simplicity | Delete the feature. What's the smallest thing that could possibly work? |
| Scale-to-1000× | Design as if load/users/data were 1000× today. What breaks, what survives? |
| Future-legacy | It's 3 years later and this is the part everyone hates. What was it, and the fix? |
| User-extreme | Design for the most impatient / least technical / most hostile user only. |
| Cost-obsessed | Cheapest possible build. What do you cut, fake, or defer? |
| Reliability-obsessed | Zero-downtime, zero-data-loss. What does paranoia demand? |

Frame choice is judgment — match frames to the problem. Adversary + Radical-simplicity + First-principles is a strong default trio; add 2 domain-fitting frames.

### Spawn mechanism per tool (portability)

| Tool | Parallel isolated spawn | Support |
|------|------------------------|---------|
| Claude Code | `Agent` tool — 5 blocks in one message, `subagent_type: general-purpose` | ✅ full |
| Gemini CLI | shell `&` fan-out + `wait` (5× `gemini -p "<frame prompt>"`), then read outputs | ✅ full |
| Cursor | background agent tabs opened together | ⚠️ manual |
| Copilot / Codex / Crush | no programmatic fan-out — run frames one-by-one in separate chats, paste outputs to the critic | ⚠️ degraded — sequential, not truly isolated; state the limitation to the user |

On degraded tools, still run distinct frames — you lose isolation, not divergence.

---

## Phase 2 — Focus (sequential)

Converge the ~30 ideas. Escalate this pass for high-stakes calls.

1. **Score** each idea 0–10 on three axes → weighted total:
   `score = novelty·0.35 + viability·0.40 + fit·0.25`
   - **novelty** — non-obvious, not the textbook answer
   - **viability** — buildable with current stack/constraints
   - **fit** — actually solves the stated problem
2. **Cluster** by underlying angle — collapse near-duplicates, name each cluster.
3. **Flag traps** — ideas that sound clever but hide a fatal assumption. Name the assumption.
4. **Deepen top 3** — one agent call each (parallel): concrete sketch, main risk, first step, 1–2 child ideas it unlocks.

---

## Output

```
IDEATION — <problem, one line>
Frames: <5 chosen>

WIDE SET (clustered)
▸ <cluster name>
  - <idea> — <score> (n/v/f)
  - <idea> — <score> (n/v/f)
▸ <cluster name>
  ...

SHORTLIST (top 3 by weighted score)
1. <idea> — <score>
2. ...

FOCUS
1. <idea>
   Sketch:     <how it works>
   Risk:       <main failure mode>
   First step: <smallest concrete action>
   Unlocks:    <child idea>
2. ...

TRAPS
  - <clever-but-flawed idea> — hidden assumption: <what>

PROVOCATION
  <one uncomfortable question the shortlist still doesn't answer>
```

---

## When invoked mid-workflow

- From `/debug` — use at **Hypothesize** when there's no clear root cause after 2 isolation attempts (fuzzy debugging). Frames become candidate cause-classes.
- From `/parallel-build` — use before **Phase 1 Scaffold** when the architecture/approach is genuinely open. Feed the chosen shortlist into scaffold as the design decision.

Never auto-run from a workflow — offer it, let the user opt in (cost gate applies).
