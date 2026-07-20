---
name: think
description: Router for systems/strategy reasoning frameworks — classify the problem shape, then apply the matching mental model (systems, feedback loops, constraints, leverage, cynefin, second-order). Use for architecture, complex-system debugging, and decisions with non-obvious downstream effects. Curated from tjboudreaux/cc-thinking-skills (MIT).
alwaysApply: false
---

**Model:** everyday — escalate the analysis (`claude-opus-4-8`) for architecture calls with non-obvious tradeoffs.

> **Core behaviors:** Surface assumptions. STOP and ask when confused. See `/using-agent-skills`.
> **Reasoning aid, not an action skill.** `/think` structures *how you reason*, then hands off. It does not edit code, review, or scaffold — route to the real skill after.

---

## First: is a framework even needed?

`/think` is for problems where the naive approach misleads — interconnected systems, delayed effects, non-obvious bottlenecks. Routine code tasks do **not** need it. If the answer is clear, say so and skip.

## Route to what already exists (do NOT reinvent)

Much reasoning is already covered — send the user there instead of loading a framework:

| Need | Use |
|------|-----|
| Widen the option set — brainstorm, naming, open design | `/ideate` (first-principles, inversion, adversary frames) |
| Simplify / delete / "do we need this" | `ponytail` ladder (via-negativa, Occam) — always active |
| Root cause of a bug | `/debug` (five-whys, scientific method) |
| Argue against a plan/change | `adversarial` agent, `plan-roaster` (red-team, steel-man) |
| Is this decision hard to reverse? | `karpathy` "hard to reverse" gate + fusion-panel triggers |

Only continue below when the problem is genuinely a **systems / strategy** shape.

---

## The 6 frameworks — pick by problem shape

| Framework | Use when | Core move |
|-----------|----------|-----------|
| **Cynefin** | You don't know *what kind* of problem this is | Classify: Clear (best practice) · Complicated (analyze, expert) · Complex (probe→sense→respond, safe-to-fail experiments) · Chaotic (act→stabilize first). Match approach to domain — don't apply best-practice to a complex problem. |
| **Systems** | Parts interact; fixing one thing breaks another | Map elements → connections → the behavior they produce. Look for the structure generating the symptom, not the symptom. |
| **Feedback loops** | Behavior amplifies or self-corrects over time | Name each loop: reinforcing (snowballs — growth, runaway retries, cache stampede) vs balancing (self-limits — backpressure, rate limit). Find which loop dominates. |
| **Theory of constraints** | System is slow/limited but effort is spread thin | Find the ONE bottleneck. Improving anything else is waste until the constraint moves. (Broader than `/fe-performance` — applies to process, build, data flow.) |
| **Leverage points** | Many possible interventions, limited effort | Rank by leverage: params/numbers (weak) → feedback structure → rules → goals → paradigm (strong). Push the highest-leverage point that's feasible. |
| **Second-order** | A fix looks obviously good | Ask "and then what?" 2–3 hops out. Surface the delayed/indirect cost the first-order view hides. |

Combining is allowed: e.g. Cynefin to classify → Systems to map → Constraints to prioritize.

---

## Process

1. **Classify** — one line: what shape is this problem? (If not systems/strategy → route to the table above and stop.)
2. **Pick 1–2 frameworks** — name them and why.
3. **Apply** — run the core move. Show the map/loops/constraint/hops explicitly, not just a conclusion.
4. **Output** — the insight the framework surfaced that the naive view missed, then the concrete next action + which real skill executes it.

```
THINK — <problem, one line>
Shape:     <cynefin domain / systems / loop / constraint / …>
Framework: <chosen> — <why>

ANALYSIS
<the map / loops / bottleneck / second-order hops — shown, not asserted>

INSIGHT
<what the naive view missed>

NEXT
<concrete action> → <which skill/command executes it>
```

Keep it tight — the value is the reframe, not a wall of theory.
