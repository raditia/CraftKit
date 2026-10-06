import { readFileSync } from "node:fs";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Read at build time, so a release (which bumps package.json) redeploys the site with the new
// facts and nobody edits a version string by hand. pages.yml triggers on package.json for this.
const pkg = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
const repo = pkg.repository.url.replace(/^git\+/, "").replace(/\.git$/, "");
const url = new URL(pkg.homepage).href;
const os = { darwin: "macOS", linux: "Linux" };

const attr = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
const head = {
  DESCRIPTION: attr(pkg.description),
  URL: attr(url),
  JSONLD: JSON.stringify({
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "CraftKit",
    description: pkg.description,
    url,
    applicationCategory: "DeveloperApplication",
    operatingSystem: pkg.engines.os.map((o) => os[o] ?? o).join(", "),
    softwareVersion: pkg.version,
    license: `https://spdx.org/licenses/${pkg.license}.html`,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    sameAs: [repo, `https://www.npmjs.com/package/${pkg.name}`],
  }).replace(/</g, "\\u003c"),
};

export default defineConfig({
  // The homepage path (/CraftKit/ on Pages), not "./": the prerendered markup needs the same
  // absolute asset URLs the client build emits, or hydration keeps a broken image src.
  base: new URL(url).pathname,
  define: {
    __CRAFTKIT__: JSON.stringify({ name: pkg.name, version: pkg.version, repo }),
  },
  plugins: [
    react(),
    {
      name: "craftkit-head",
      transformIndexHtml: {
        order: "pre",
        handler: (html) => html.replace(/%(\w+)%/g, (token, key) => head[key] ?? token),
      },
    },
  ],
});
