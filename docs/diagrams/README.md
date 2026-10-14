# CraftKit diagrams

[Back to README](../../README.md) · [Detailed guide](../guide.md)

All documentation and site diagrams use **Diagram Design** with CraftKit's color palette and Diagram Design's editorial typography. Each `.html` file is the editable source; its `.svg` sibling is the diagram-only export used in Markdown and the site. SVGs embed their styles and use system font fallbacks without network requests. HTML sources request Instrument Serif, Geist and Geist Mono through Google Fonts and fall back to system fonts when offline.

## CraftKit palette

Colors come from [the site stylesheet](../../site/src/styles.css) and [site design notes](../../site/README.md#design). Typography stays Instrument Serif, Geist and Geist Mono; this update matches the brand colors. The site's Inter typography is unchanged.

### Semantic roles

| Role | Color | Use |
|---|---|---|
| `paper` | `#FAFBFC` | Page background and arrow-label masks |
| `ink` | `#0C1118` | Primary text and node outlines |
| `muted` | `#63717B` | Arrows, labels and captions on paper |
| `soft` | `#5C6973` | Subtitles; derived from muted to preserve AA contrast on tinted nodes |
| `rule-solid` | `#E0E5E8` | Decorative footer dividers |
| `accent` | `#287D78` | One or two focal nodes |
| `accent-tint` | `rgba(40,125,120,0.08)` | Focal node fill |
| `link` | `#287D78` | External-call markers |
| `node-surface` | `#FFFFFF` | Regular node fill |

The palette is local to these figures; it does not change the installed plugin's shared style guide or other projects. Body and technical labels retain the font families and weights in their HTML sources; exported SVGs disclose system fallbacks above.

## Inventory and fidelity notes

The redraws keep the subject and meaningful branches, merging detail into labels and accompanying text. Counts below exclude grouping containers. The old workflow-role legend became a table, since it describes a list of roles rather than a flow.

| Diagram | Source → drawn nodes | Redraw decisions | Files |
|---|---:|---|---|
| Distribution | 13 → 7 | Merge five content directories into one labeled input; move enforcement and verification notes to the caption. Keep four independent tool destinations | [HTML](sync-engine.html) · [SVG](sync-engine.svg) |
| Current runtime | 12 → 6 | Merge loader/router/guards/exit into Gateway; merge skill and agent workers; combine intent, cases and published-view notes. Keep host MCP separate | [HTML](runtime.html) · [SVG](runtime.svg) |
| Platform routing | 10 → 5 | Combine platform destinations into a classification step; preserve the parent-directory loop. Marker-to-platform mapping remains in the guide and routing hook | [HTML](platform-routing.html) · [SVG](platform-routing.svg) |
| Parallel review | 7 → 6 | Combine request and routing into context. Preserve the failed-gate branch, parallel tests/reviews and synthesis; verdicts remain in the caption | [HTML](parallel-review.html) · [SVG](parallel-review.svg) |
| Parallel ship | 7 → 6 | Same handoffs as review, with the project coverage gate named explicitly | [HTML](parallel-ship.html) · [SVG](parallel-ship.svg) |
| Parallel build | 7 → 6 | Group scaffold/implementation with context; distinguish test authoring during reviews from the later test run | [HTML](parallel-build.html) · [SVG](parallel-build.svg) |
| Finding synthesis | 19 → 6 | Merge reviewer types; group confidence classes and contradictions into deduplication. Preserve adversarial blind spots, coverage gaps and verdict rules. Drop four decorative stage headers | [HTML](synthesis.html) · [SVG](synthesis.svg) |
| Sequential fallback | 6 → 5 | Merge the final execution handoff into the announced command. Keep parallel/sequential branches and the lost-validation note | [HTML](fallback.html) · [SVG](fallback.svg) |
| Planning | 29 → 7 | Isolate the planning stages, approvals and optional ideation/roast. Build/review/ship detail lives in their own figures; the separate bug-fix path stays in the guide's fix section | [HTML](planning.html) · [SVG](planning.svg) |
| Agent teams | 7 → 5 | Merge explicit request with runtime preflight and integration checks with the final report. Preserve file ownership and staged reviewer/tester handoffs | [HTML](team-build.html) · [SVG](team-build.svg) |
| Cross-review | 8 → 6 | Merge request with preflight and both provider rounds into one labeled panel. Keep preflight and reply-validation failures; combine adjudication/reporting | [HTML](cross-review.html) · [SVG](cross-review.svg) |
| Context flow | 7 → 6 | Merge evaluation and documentation as consumers of intent. Preserve the separate context/intent inputs and their review connections | [HTML](context-flow.html) · [SVG](context-flow.svg) |
| Claude model routing | 8 → 7 | Merge the per-prompt hook into the account-data decision. Preserve alias fallback, plan windows and entitlement selection | [HTML](model-routing.html) · [SVG](model-routing.svg) |
| Tool model selectors | 13 → 6 | Merge each tool with its selector and collapse the tier/tool chooser. Retain the self-updating outcome, Cursor limitation and content gate | [HTML](tool-models.html) · [SVG](tool-models.svg) |
| Historical runtime proposal | 11 → 8 | Merge four Gateway components. Preserve skill/MCP access, skill read/write, agent reads and the published export. Label it historical; current support is in the runtime figure | [HTML](historical-runtime.html) · [SVG](historical-runtime.svg) |
| Frontend roles | 5 → 5 | Replace the text module tree with the five EVPMR roles; keep file naming and layer constraints in the guide | [HTML](evpmr.html) · [SVG](evpmr.svg) |

The distribution figure replaces the site's former generated PNG. The walkthrough reuses the build figure and retains its interactive stage explanations. The social preview is a capture of the updated hero. Terminal snapshots, skill discovery lists and code/prompt examples remain textual references.

## Source and size choices

Architecture views show system relationships; flowcharts show decisions and failure paths. Sources use a `960 × 600` doc-inline canvas, except context flow, cross-review and the historical runtime map, which use a `1008 × 600` fit canvas to leave room for return routes. All are balanced or simplified views for a mixed technical audience, with no animation.

The Mermaid importer accepted eight README blocks and both other documentation blocks. These imports reported errors and were **not** rendered or approximated by the importer:

```text
README block 4: mermaid_extract: not a Mermaid file at line 602
README block 5: mermaid_extract: not a Mermaid file at line 664
README block 6: mermaid_extract: not a Mermaid file at line 726
README block 9: mermaid_extract: malformed edge at line 967
README block 10: mermaid_extract: not a Mermaid file at line 1053
README block 11: mermaid_extract: not a Mermaid file at line 1116
```

Their replacements were authored from `commands/parallel-review.md`, `commands/parallel-ship.md`, `commands/parallel-build.md`, `commands/define.md`, `commands/team-build.md` and `commands/cross-review.md`. The original planning overview mixed four workflows and a bug-fix path; the new figures separate those subjects.

## Maintain a diagram

1. Read the relevant command, rule or adapter before changing its diagram. Update the HTML through Diagram Design; use the CraftKit palette above and preserve meaningful branches and accessible title/description.
2. Run Diagram Design's `scripts/self_check.py` on the HTML. From the plugin root, also run `scripts/verify-geometry.py`. Use `scripts/lint-skin.py`'s `lint_text` with the semantic palette above rather than its installed default palette; verify text contrast on both paper and tinted nodes.
3. Export the HTML through `scripts/export_svg.py <source.html> <output.svg> --system-fonts`. Edit the HTML source first; regenerate its SVG sibling.
4. Inspect the rendered HTML and SVG. Check that small screens scroll each diagram locally, labels stay inside the canvas and connectors do not cross unrelated nodes.
5. For a distribution change, update `site/src/repo.js` and the shared sync figure. For a workflow change, update its guide text and site explanations. Regenerate `site/public/og.png` after a hero change.
6. Run `bash check.sh`, the site build when affected, then `bash sync.sh` twice. The second sync must report everything up to date.

The diagram HTML keeps the full editable figure. SVG exports keep its title, description and namespaced markers. They intentionally omit the HTML wrapper and page heading.
