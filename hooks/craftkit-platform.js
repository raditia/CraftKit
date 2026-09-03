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
  { key: 'fe', label: 'React Native / web (EVPMR)', match: n => n === 'package.json' },
];

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
    const hits = PLATFORM_MARKERS.filter(p => entries.some(n => p.match(n)));
    if (hits.length) return { label: hits.map(p => p.label).join(' + '), keys: hits.map(p => p.key) };
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return { label: null, keys: [] };
}

module.exports = { detectPlatform };
