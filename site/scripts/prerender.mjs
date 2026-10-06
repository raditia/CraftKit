// Writes the server-rendered page into dist/index.html, so crawlers and link previews that
// don't run JavaScript see the real content. main.jsx hydrates it in the browser.
import { readFileSync, rmSync, writeFileSync } from "node:fs";

const ssrDir = new URL("../dist-ssr/", import.meta.url);
const page = new URL("../dist/index.html", import.meta.url);
const { render } = await import(new URL("entry-server.js", ssrDir));

const html = readFileSync(page, "utf8");
const mount = '<div id="root"></div>';
if (!html.includes(mount)) throw new Error(`prerender: ${mount} not found in dist/index.html`);
writeFileSync(page, html.replace(mount, `<div id="root">${render()}</div>`));
rmSync(ssrDir, { recursive: true });
