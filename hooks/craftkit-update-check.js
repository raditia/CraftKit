#!/usr/bin/env node
// CraftKit SessionStart hook: tells the user when a newer craftkit is on npm.
// npm never notifies an installed package's users, and craftkit has no CLI they run, so
// without this a release reaches only the people who go looking for it.
// The registry is asked at most once a day; the answer is cached in the state dir sync.sh
// already owns. Every failure (offline, timeout, bad JSON, no version file) stays silent,
// because a broken update check must never cost a session anything.
// Escape hatch: CRAFTKIT_UPDATE_CHECK=off.

const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');

const STATE = path.join(os.homedir(), '.craftkit-state');
const VERSION_FILE = path.join(STATE, 'version');
const CACHE_FILE = path.join(STATE, 'update-check');
const REGISTRY = 'https://registry.npmjs.org/@raditia/craftkit/latest';
const DAY_MS = 24 * 60 * 60 * 1000;
// ponytail: blocks session start up to this long, once a day. ceiling: slow networks feel it daily. upgrade: refresh the cache in a detached child and report from cache only.
const TIMEOUT_MS = 1500;

const pass = () => process.stdout.write('{}');

// Numeric per dot-segment, matching sync.sh's sort -V guard, so 1.9.0 stays below 1.10.0.
function newer(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

function fetchLatest(done) {
  const req = https.get(REGISTRY, { timeout: TIMEOUT_MS, headers: { Accept: 'application/json' } }, res => {
    let body = '';
    res.on('data', c => { body += c; });
    res.on('end', () => {
      try { done(JSON.parse(body).version || ''); } catch (e) { done(''); }
    });
  });
  req.on('timeout', () => req.destroy());
  req.on('error', () => done(''));
}

function report(installed, latest) {
  if (!latest || !newer(latest, installed)) return pass();
  process.stdout.write(JSON.stringify({
    systemMessage:
      'craftkit v' + latest + ' is available (installed: v' + installed + '). ' +
      'Update: npm i -g @raditia/craftkit@latest, or git pull in a cloned checkout. ' +
      'Notes: https://github.com/raditia/CraftKit/releases'
  }));
}

process.stdin.resume();
process.stdin.on('data', () => {});
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_UPDATE_CHECK === 'off') return pass();

  let installed;
  try { installed = fs.readFileSync(VERSION_FILE, 'utf8').trim(); } catch (e) { return pass(); }
  if (!installed) return pass();

  let cache = {};
  try { cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8')); } catch (e) { /* refetch */ }
  if (cache.checked && Date.now() - cache.checked < DAY_MS) return report(installed, cache.latest);

  fetchLatest(latest => {
    // A failed fetch is cached too, so an offline machine pays the timeout once a day, not per session.
    try { fs.writeFileSync(CACHE_FILE, JSON.stringify({ checked: Date.now(), latest: latest || cache.latest || '' })); } catch (e) { /* stays uncached */ }
    report(installed, latest || cache.latest);
  });
});
