#!/usr/bin/env node
// Usage: node scripts/skill-usage.js [usage.jsonl]
// Reads the log hooks/craftkit-skill-usage.js writes (default ~/.craftkit/skill-usage.jsonl)
// and lists every skill and command in this repo with calls, sessions and first/last use.
const fs = require('fs');
const os = require('os');
const path = require('path');

const root = path.join(__dirname, '..');
const file = process.argv[2] || path.join(os.homedir(), '.craftkit', 'skill-usage.jsonl');
const names = [
  ...fs.readdirSync(path.join(root, 'skills'), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name),
  ...fs.readdirSync(path.join(root, 'commands')).filter((f) => f.endsWith('.md')).map((f) => f.slice(0, -3)),
];

const stats = {};
let lines = [];
try { lines = fs.readFileSync(file, 'utf8').split('\n'); } catch (e) { console.log(`no usage log at ${file}`); }
for (const l of lines) {
  let r;
  try { r = JSON.parse(l); } catch (e) { continue; }
  if (!r || typeof r.skill !== 'string' || !Number.isFinite(r.ts)) continue;
  const name = r.skill.replace(/^.*:/, '');
  const s = stats[name] || (stats[name] = { calls: 0, errors: 0, sessions: new Set(), first: r.ts, last: r.ts });
  s.calls++;
  if (r.error) s.errors++;
  s.sessions.add(r.session);
  s.first = Math.min(s.first, r.ts);
  s.last = Math.max(s.last, r.ts);
}

const day = (t) => new Date(t * 1000).toISOString().slice(0, 10);
const used = names.filter((n) => stats[n]).sort((a, b) => stats[b].calls - stats[a].calls);
console.log('skill\tcalls\terrors\tsessions\tfirst\tlast');
for (const n of used) {
  const s = stats[n];
  console.log(`${n}\t${s.calls}\t${s.errors}\t${s.sessions.size}\t${day(s.first)}\t${day(s.last)}`);
}
console.log('\nnever used:');
for (const n of names.filter((x) => !stats[x]).sort()) console.log(`  ${n}`);
