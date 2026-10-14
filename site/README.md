# CraftKit site

The landing page published at https://raditia.github.io/CraftKit/. Vite + React, a single page, not part of the npm package.

```sh
cd site
npm ci
npm run dev       # local preview
npm run build     # static output in site/dist
npm run preview   # serve the build at http://localhost:4173/CraftKit/
```

The build prerenders the page into `dist/index.html` (`scripts/prerender.mjs`) and `src/main.jsx` hydrates it, so crawlers and link previews that skip JavaScript still read the full page.

## How it stays in sync with the repo

| Kind of fact | Examples | How it stays current |
|---|---|---|
| Derived | version, npm package name, description, repo URL, canonical URL and base path (`homepage`), Open Graph tags, JSON-LD | Read from the root `package.json` at build time (`vite.config.mjs`). `.github/workflows/pages.yml` redeploys on every push to `main` that touches `package.json`, `site/` or `docs/diagrams/`, so releases and diagram edits refresh the page |
| Referenced | README anchors, repo file links, workflow command names, the four tools | Written through `readme()`, `repoFile()`, `command:` and `TOOLS` in `src/`. `check.sh` check 41 resolves each one, so a renamed heading, moved file, renamed command, or added adapter fails the PR |
| Judgment | workflow copy, the walkthrough, the hero illustration, `public/og.png` | Update by hand in the same change as the repo edit, per the sync matrix in `CLAUDE.md` |

Write every link to the repo through the helpers in `src/repo.js`; check 41 fails on a hardcoded `github.com` URL because the gate can't see it.

`public/og.png` is a 1200×630 capture of the updated hero in a compact layout. After a hero change, rebuild the site and run `npm run preview`. Capture it at 1200×630 with these temporary preview styles (do not add them to the application stylesheet):

```css
.header { height: 44px; }
.hero { padding-top: 8px; }
.hero-copy .badge, .hero-actions, .hero-copy .copy-wrap { display: none; }
.hero-copy h1 { font-size: 40px; letter-spacing: -1.5px; margin: 12px 0; }
.hero-description { font-size: 14px; }
.sync-figure { width: 680px; margin: 12px auto 0; }
.sync-figure img { min-width: 0; width: 680px; }
.workflow-section { display: none; }
```

Wait for the bundled fonts and images to load before capture. The full distribution diagram must fit inside the preview, including all four tool destinations.

There is no `robots.txt` or sitemap here: crawlers read those only at the domain root, which is the `raditia.github.io` user site.

## Design

- Clean cool-white background `#FAFBFC`, muted turquoise `#287D78` accents, neutral gray dividers. No warm paper tones, glow, or concentric rings.
- Minimal: plain eyebrow text, fine dividers, soft palette. Inter is bundled; Phosphor supplies icons.
- "AI-gnostic" is a tagline under the wordmark, not a product rename.
- The diagram gallery at `#diagrams` derives its list from `docs/diagrams/*.svg`. Rows expand with native keyboard-accessible controls, keep diagrams readable with local horizontal scrolling, and link to the full-size SVG and editable HTML source.
- The hero, walkthrough and gallery reuse the Diagram Design SVGs in `../docs/diagrams/`. Their editable HTML sources, style choice and redraw notes are listed in [the diagram inventory](../docs/diagrams/README.md). Adding a tool means updating the distribution diagram and exporting it again.
- The walkthrough follows the stage order in `commands/parallel-build.md` (context, scaffold and implement, fast gates, classifier, parallel read-only reviews alongside test authoring, synthesize and fix, run tests, handoff), with natural-language example requests rather than slash-command snippets.
- Product facts come from this repo. No invented adoption metrics or guaranteed savings.
