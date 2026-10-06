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
| Derived | version, npm package name, description, repo URL, canonical URL and base path (`homepage`), Open Graph tags, JSON-LD | Read from the root `package.json` at build time (`vite.config.mjs`). `.github/workflows/pages.yml` redeploys on every push to `main` that touches `package.json` or `site/`, so each release refreshes them |
| Referenced | README anchors, repo file links, workflow command names, the four tools | Written through `readme()`, `repoFile()`, `command:` and `TOOLS` in `src/`. `check.sh` check 41 resolves each one, so a renamed heading, moved file, renamed command, or added adapter fails the PR |
| Judgment | workflow copy, the walkthrough, the hero illustration, `public/og.png` | Update by hand in the same change as the repo edit, per the sync matrix in `CLAUDE.md` |

Write every link to the repo through the helpers in `src/repo.js`; check 41 fails on a hardcoded `github.com` URL because the gate can't see it.

`public/og.png` is the social preview card, a 1200x630 capture of the hero. After a hero change, regenerate it with `npm run preview` running:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 \
  --window-size=1200,760 --screenshot=/tmp/og.png http://localhost:4173/CraftKit/
sips --cropToHeightWidth 630 1200 --cropOffset 78 0 /tmp/og.png --out public/og.png
```

There is no `robots.txt` or sitemap here: crawlers read those only at the domain root, which is the `raditia.github.io` user site.

## Design

- Clean cool-white background `#FAFBFC`, muted turquoise `#287D78` accents, neutral gray dividers. No warm paper tones, glow, or concentric rings.
- Minimal: plain eyebrow text, fine dividers, soft palette. Inter is bundled; Phosphor supplies icons.
- "AI-gnostic" is a tagline under the wordmark, not a product rename.
- `src/assets/sync-engine.png` is an AI-generated concept illustration that draws the four tools. Adding a tool means regenerating it.
- The walkthrough follows the stage order in `commands/parallel-build.md` (context, scaffold and implement, fast gates, classifier, parallel read-only reviews alongside test authoring, synthesize and fix, run tests, handoff), with natural-language example requests rather than slash-command snippets.
- Product facts come from this repo. No invented adoption metrics or guaranteed savings.
