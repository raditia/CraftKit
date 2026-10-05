#!/usr/bin/env node
// Shared platform detection for the CraftKit hooks. Two hooks decide on "what platform is
// this directory", and a disagreement between them would route the prompt to one platform's
// skills while loading another platform's rules, which is worse than either being wrong
// alone. Defined once here, required by relative path.
// Installed alongside the hooks by adapters/claude.sh.

const fs = require('fs');
const path = require('path');

// `key` is the short name a rule's `platform:` frontmatter names; `label` is the prose the
// routing hook shows the model. Both come from one row so they cannot drift.
const PLATFORM_MARKERS = [
  { key: 'android', label: 'Android (MVP)', match: n => /^(settings|build)\.gradle(\.kts)?$/.test(n) },
  { key: 'ios', label: 'iOS (MVVM-C)', match: n => n === 'Package.swift' || n === 'Podfile' || /\.xc(odeproj|workspace)$/.test(n) },
  { key: 'node', label: 'Node / tooling', match: n => n === 'package.json' },
];

const readJson = file => { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return null; } };

function usesReact(dir) {
  const pkg = readJson(path.join(dir, 'package.json'));
  if (!pkg) return false;
  const deps = { ...pkg.dependencies, ...pkg.devDependencies, ...pkg.peerDependencies };
  return ['react', 'react-native', 'react-dom', 'next', 'expo'].some(n => n in deps);
}

// A monorepo root often carries no React dependency itself (district-traveloka keeps it in
// packages/apps), so a root-only check routed the RN monorepo as plain Node. Workspace
// packages come from package.json `workspaces`, lerna.json `packages`, or pnpm-workspace.yaml.
// ponytail: globs expand only `dir/*` and literal paths. ceiling: `**` or negations are skipped. upgrade: a glob lib if a repo needs them.
function workspaceDirs(dir) {
  const pkg = readJson(path.join(dir, 'package.json')) || {};
  const ws = pkg.workspaces;
  let globs = [].concat(Array.isArray(ws) ? ws : (ws && ws.packages) || [],
    (readJson(path.join(dir, 'lerna.json')) || {}).packages || []);
  try {
    const yaml = fs.readFileSync(path.join(dir, 'pnpm-workspace.yaml'), 'utf8');
    globs = globs.concat([...yaml.matchAll(/^\s*-\s*['"]?([^'"\s#]+)/gm)].map(m => m[1]));
  } catch (_) {}
  return globs.flatMap(g => {
    if (g.startsWith('!') || g.includes('**')) return [];
    if (!g.endsWith('/*')) return [path.join(dir, g)];
    const base = path.join(dir, g.slice(0, -2));
    try { return fs.readdirSync(base).map(n => path.join(base, n)); } catch (_) { return []; }
  });
}

// Walks up from startDir to the first directory carrying any marker. A monorepo root with
// several markers returns all of them, so a mixed repo loads every relevant platform's
// rules rather than silently picking one.
function detectPlatform(startDir) {
  let dir = startDir;
  while (true) {
    let entries;
    try {
      entries = fs.readdirSync(dir);
    } catch (e) {
      return { label: null, keys: [] };
    }
    const hits = PLATFORM_MARKERS.filter(p => entries.some(n => p.match(n))).map(p => {
      if (p.key !== 'node') return p;
      const pkgDirs = [dir].concat(workspaceDirs(dir));
      return pkgDirs.some(usesReact) ? { key: 'fe', label: 'React Native / web (EVPMR)' } : p;
    });
    if (hits.length) return { label: hits.map(p => p.label).join(' + '), keys: hits.map(p => p.key) };
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return { label: null, keys: [] };
}

module.exports = { detectPlatform };
