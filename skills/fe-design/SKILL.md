---
name: fe-design
description: Catch design that reads as AI-generated: default gradients and glassmorphism, template layouts, bento grids, decorative icon and badge filler, invented dashboard numbers, and responsive layouts that break on mobile. Use when building or reviewing any screen's visual design, not its correctness. Adapted from miqdadbadjuber/anti-slop (MIT).
alwaysApply: false
craftkitInject: external-sources
---

**Commands:** none required. Read the changed `View*.tsx` and its `StyleSheet`
**Model:** cheapest tier (see the plan-aware Model routing table in `using-agent-skills`). Escalate to everyday when judging whether a technique earns its place is genuinely contested.

---

**Context:** Derived context for the change (Summary + Changed Files), emitted by `/fe-context`. Read the changed `View*.tsx` and any `UI*` sub-components. When your caller passed a slug, read its Figma source per `external-sources`: a choice the design file makes deliberately is intent, not a model default.

> **Visual design only.** Correctness, dead controls and layer violations belong to `/fe-review` and `/code-quality`. Contrast ratios, tap-target sizes, focus order and keyboard paths belong to `/fe-a11y`. Product copy belongs to `/humanizer`. Inline styles, `StyleSheet.create` and design tokens are already laws in `fe-rules`. This skill judges one thing: whether the design has a character of its own, or wears the model's defaults.

---

## Trigger

User says: "does this look AI-generated", "review the design", "this screen looks generic", "make this look less like a template", or invokes `/fe-design`.

---

## The purpose test

The filter rejects technique **without purpose**, not technique itself. Before any visual choice, answer: what does this serve? If the only answer is "it looks modern" or "it looks safe", it goes. If the answer names a hierarchy, identity or readability goal, it stays and the reason gets written down next to it.

The question that decides done:

> Swap out the logo and product name. Does this screen still have a character of its own?

No means generic. A gradient that separates one level of hierarchy from another is craft; the same gradient on every section is a default.

---

## Visual and colour

| Tell | Fix |
|---|---|
| Blue-to-purple, blue-to-cyan or purple-to-pink as the primary treatment; full-page coloured glow; radial orbs behind the hero | Pull the palette from the product's own identity. Keep a gradient only where it marks hierarchy, with the reason written down |
| Blur or `backdrop-filter` on navbar, cards, modals and sidebar at once | Glass is an accent, not a character trait. Cap it at one or two elements: the surface that needs the attention |
| Large radius on every corner, uniformly | Radius carries meaning: interactive versus static, nested versus top level. Uniform radius carries none |
| Soft shadow on every element, so everything floats | Shadow is an elevation marker. Selective, with the elevation reason stated |
| Glow on buttons, borders and text | Glow for one focal point at most, or none |
| Faint grid or dot pattern as page background | Background carries brand or nothing |
| Dark mode as the default with no product reason | Pick the default the product's use context calls for, and make both themes actually work |
| More than roughly five palette entries, or an accent on every surface | One accent, used where it directs attention. A palette that highlights everything highlights nothing |
| Pure greyscale with a single blue accent and no identity | Sterile is also a default. Neutral is a choice only when something else carries the character |

## Layout and components

| Tell | Fix |
|---|---|
| Hero, three feature cards, logo bar, pricing, FAQ, CTA footer, in that order | Order sections by what this product has to prove, not by template sequence |
| Feature cards identical but for icon and label | Cards differ when the content differs. Identical cards mean the content was invented to fill them |
| Bento grid with no size logic | Cell size encodes importance. Equal-weight content is a list, not a bento |
| One spacing value everywhere | Spacing groups and separates. Use `Token.spacing` steps to mean something, not to be uniform |
| "How it works" in exactly three steps | Use the number of steps the process has |
| "Trusted by" logo bar with no real customers | Cut it, or use real logos you have permission for |
| "Most popular" on the middle pricing tier by reflex | Mark the tier you actually want chosen, or mark none |
| A product demo rendered as static mockup | Show the real thing, or say plainly it is a placeholder |
| Four-column footer padded to fill | Footer holds what people need. Two links is a fine footer |
| Every section the same height and rhythm | Vary density by importance; even rhythm flattens the page |

## Decoration

| Tell | Fix |
|---|---|
| Rocket, sparkle, lightning, brain icons | Icons name the thing they sit beside, or go |
| The same icon set's defaults on everything | An icon set is a starting point, not a design |
| Emoji as section decoration | Emoji when it carries meaning, not as texture |
| A small arrow on every button | Arrow when it signals navigation, not as button seasoning |
| Coloured left stripe on cards and callouts | One stripe with a status meaning, or none |
| Capsule badges reading "AI-powered", "Smart", "Fast" | Say the specific capability, or say nothing |
| Eyebrow badge above every headline | Eyebrow only when it carries information the headline cannot |
| A pulsing green status dot with nothing behind it | A status indicator reflects real status |
| Fake terminal window with invented output | Real output, or no terminal |
| Illustrations unconnected to the product | Imagery references the actual domain |

## App and dashboard

| Tell | Fix |
|---|---|
| Sidebar, topbar, four stat cards, chart, table: the default shell | Layout follows the job the screen does |
| Stat cards carrying invented numbers | Real numbers, or an honest empty state. **Never fabricate a metric** |
| Activity feed padded with plausible-looking events | Real events or an empty state |
| A chart that answers no question | Every chart answers a stated question, or goes |
| Generic table columns (Name, Status, Date, Actions) | Columns the user actually needs to sort and scan by |
| Lorem-flavoured filler in fields and columns | Real sample data, or blank |
| Empty and loading states that just say "No data" or spin | Empty states say what goes here and how to start; loading states preserve layout |

## Responsive and mobile

| Tell | Fix |
|---|---|
| Layout designed at desktop width, mobile treated as a fallback | Design the narrow case first; it is the constrained one |
| Breakpoints named after device models | Breakpoints go where the layout actually breaks |
| Two states only, desktop and phone, nothing between | Check the middle widths; tablet is where template layouts fail |
| Fixed pixel type that never scales | Scalable type, and honour the platform's text-size setting |
| `100vh` sections | Mobile browser chrome makes `100vh` overflow. Use the dynamic viewport unit or content height |
| Desktop padding carried onto small screens | Padding scales with the viewport |
| Columns that never collapse, fixed-width grids, forced twelve columns | Let the grid reflow; a grid that cannot collapse is a desktop layout wearing a grid |
| Horizontal scroll leak, or `overflow: hidden` hiding the symptom | Find the child that exceeds the viewport. Hiding overflow hides the bug, not the cause |

## Motion

| Tell | Fix |
|---|---|
| Endless pulses, floats and looping ambient motion | Motion marks a state change. Continuous motion marks nothing and costs battery |
| Fade, slide and scale stacked on one element | One transition per state change |

---

## Output

One finding per line, with the severity labels from `using-agent-skills`:

```
[ERROR]       file:line: fabricated metric, "10K+ users", no source
                Fix: real number or an honest empty state
[WARNING]     file:line: blur on navbar + cards + modal, so nothing is foreground
                Fix: glass on the one surface that needs attention
[SUGGESTION]  file:line: three feature cards identical but for icon
                Fix: differentiate, or cut to the features that differ
```

Fabricated numbers, testimonials and logos are `[ERROR]`: they are honesty failures, not taste. Everything else is `[WARNING]` or `[SUGGESTION]`, and the author decides.

End with the purpose test verdict:

```
PURPOSE TEST: pass | fail
  Swap the logo and name: <does it still have a character of its own, and what carries it>
```

---

## Boundaries

Judges visual design only. It does not edit code, does not touch correctness, accessibility or copy, and does not invent a brand palette: where identity is undefined, it says so and asks rather than picking one.

Adapted from [miqdadbadjuber/anti-slop](https://github.com/miqdadbadjuber/anti-slop) (MIT), specifically its `antislop-ui` and `antislop-layoutmobile` skills, compressed to one line per entry and with the entries craftkit already covers elsewhere removed in favour of pointers.
