---
name: think
description: Router for systems/strategy reasoning frameworks. Classify the problem shape, then apply the matching mental model (cynefin, systems, constraints, second-order). Use for architecture, complex-system debugging, and decisions with non-obvious downstream effects. Curated from tjboudreaux/cc-thinking-skills (MIT).
alwaysApply: false
---

**Model:** everyday. Escalate the analysis for architecture calls with non-obvious tradeoffs.

> **Core behaviors:** Surface assumptions. STOP and ask when confused. See `/using-agent-skills`.
> **Reasoning aid, not an action skill.** `/think` structures *how you reason*, then hands off. It does not edit code, review, or scaffold; route to the real skill after.

---

## First: is a framework even needed?

`/think` is for problems where the naive approach misleads: interconnected systems, delayed effects, non-obvious bottlenecks. Routine code tasks do **not** need it. If the answer is clear, say so and skip.

## Route to what already exists (do NOT reinvent)

Much reasoning is already covered, so send the user there instead of loading a framework:

| Need | Use |
|------|-----|
| Widen the option set: brainstorm, naming, open design | `/ideate` (first-principles, inversion, adversary frames) |
| Simplify / delete / "do we need this" | `ponytail` ladder (via-negativa, Occam), always active |
| Root cause of a bug | `/debug` (five-whys, scientific method) |
| Argue against a plan/change | `adversarial` agent, `plan-roaster` (red-team, steel-man) |
| Is this decision hard to reverse? | Fusion-panel triggers in `using-agent-skills` ("Irreversible production changes") |

Only continue below when the problem is genuinely a **systems / strategy** shape.

---

## The 4 frameworks: pick by problem shape

| Framework | Use when | Core move |
|-----------|----------|-----------|
| **Cynefin** | You don't know *what kind* of problem this is | Classify: Clear (best practice) · Complicated (analyze, expert) · Complex (probe→sense→respond, safe-to-fail experiments) · Chaotic (act→stabilize first). Match approach to domain, and don't apply best-practice to a complex problem. |
| **Systems** | Parts interact, effects arrive late, or fixing one thing breaks another | Draw the boundary. Map stocks (what accumulates: queue depth, cache, debt) and the flows that fill or drain them. Name each loop as reinforcing (snowballs: runaway retries, cache stampede) or balancing (self-limits: backpressure, rate limit), with its delay, and find which dominates. Rank leverage points: params/numbers (weak) → feedback structure → rules → goals → paradigm (strong), then push the highest feasible one. |
| **Theory of constraints** | System is slow/limited but effort is spread thin | Find the ONE bottleneck. Improving anything else is waste until the constraint moves. (Broader than `/fe-performance`, since it applies to process, build, data flow.) |
| **Second-order** | A fix looks obviously good | Ask "and then what?" 2–3 hops out. Surface the delayed/indirect cost the first-order view hides. |

Combining is allowed: e.g. Cynefin to classify → Systems to map → Constraints to prioritize.

---

## Process

1. **Classify** in one line: what shape is this problem? (If not systems/strategy → route to the table above and stop.)
2. **Pick 1–2 frameworks** and name them and why.
3. **Apply** the core move. Show the map/loops/constraint/hops explicitly, not just a conclusion. Systems stops once the dominant loop and one feasible leverage point are named; a problem with no loop or delay is not a systems shape, so drop the framework rather than draw one.
4. **Output** the insight the framework surfaced that the naive view missed, then the concrete next action + which real skill executes it.

```
THINK: <problem, one line>
Shape:     <cynefin domain / systems / loop / constraint / …>
Framework: <chosen> · <why>

ANALYSIS
<the map / loops / bottleneck / second-order hops, shown, not asserted>

INSIGHT
<what the naive view missed>

NEXT
<concrete action> → <which skill/command executes it>
```

Keep it tight, because the value is the reframe, not a wall of theory.
