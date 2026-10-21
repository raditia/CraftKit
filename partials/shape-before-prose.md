---
name: shape-before-prose
description: Pick tables, diagrams or lists over paragraphs by the content's shape, under a length budget, for any document a human reads.
---

## Shape before prose

Readers scan first. Pick each section's form by the shape of its content, and keep prose for what no table or diagram can hold.

| Content shape | Form |
|---|---|
| Items compared on the same attributes (options, states, roles, configs, limits) | Table |
| A flow across components, a request path, a sequence of systems | Diagram |
| States and their transitions | Diagram, or a `from \| event \| to` table |
| Actions the reader performs in order | Numbered list |
| A why, a tradeoff, a caveat | 1 to 3 sentences |

Budget:
- Open every section with a one-line answer. Add detail only where a reader would act on it.
- Paragraphs stay at 3 sentences or fewer. A paragraph naming 3+ parallel items becomes a list or table.
- A table or diagram replaces the prose it covers; the text around it adds only what the visual lacks.

Diagrams go in a `text` fence as boxes and arrows, which renders the same in a terminal, on GitHub, and pasted into Confluence:

```text
App ──search──▶ Search API ──query──▶ Inventory
                    │
                    └──cache hit──▶ Redis
```

Mermaid renders only where the viewer supports it (GitHub does; Confluence needs a macro), so use it only when the user asks.
