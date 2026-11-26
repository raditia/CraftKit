#!/usr/bin/env node
// On-demand routing eval. COSTS API CALLS: one `claude -p` run per row of evals/routing.tsv.
// Not run by check.sh or CI.
// Usage: node scripts/skill-evals.js [--skill NAME] [--limit N] [--min PCT]
// For each prompt it records the first Skill tool call the model makes (none when it makes
// no Skill call) and compares it with the expected column. Exits 1 when the overall pass
// rate is under --min (default 0, report only).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i < 0 ? d : argv[i + 1]; };
const only = opt('--skill', '');
const limit = Number(opt('--limit', 0)) || Infinity;
const min = Number(opt('--min', 0));

const rows = fs.readFileSync(path.join(__dirname, '..', 'evals', 'routing.tsv'), 'utf8')
  .split('\n').slice(1).filter(Boolean).map((l) => l.split('\t'))
  .filter(([, exp]) => !only || exp === only).slice(0, limit);

// The routing hook detects the platform from cwd, so a platform skill only routes inside a
// project of that platform. Run fe-/android-/ios- rows in a minimal temp project for it.
const FIXTURES = {
  fe: { 'package.json': '{"dependencies":{"react-native":"0.76.0"}}', 'src/cart/ViewCart.tsx': 'export const ViewCart = () => null;\n' },
  android: { 'settings.gradle': 'include ":app"\n', 'app/src/main/java/cart/CartPresenter.kt': 'class CartPresenter\n' },
  ios: { 'Package.swift': '// swift-tools-version:5.9\n', 'Modules/Cart/CartViewModel.swift': 'final class CartViewModel {}\n' },
};
const cwds = {};
function cwdFor(exp) {
  const key = Object.keys(FIXTURES).find((k) => exp.startsWith(k + '-'));
  if (!key) return path.join(__dirname, '..');
  if (!cwds[key]) {
    cwds[key] = fs.mkdtempSync(path.join(os.tmpdir(), `skill-evals-${key}-`));
    for (const [f, body] of Object.entries(FIXTURES[key])) {
      fs.mkdirSync(path.dirname(path.join(cwds[key], f)), { recursive: true });
      fs.writeFileSync(path.join(cwds[key], f), body);
    }
  }
  return cwds[key];
}

function routed(prompt, exp) {
  return new Promise((resolve) => {
    const p = spawn('claude', ['-p', prompt, '--output-format', 'stream-json', '--verbose',
      '--disallowedTools', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Bash'], { cwd: cwdFor(exp), stdio: ['ignore', 'pipe', 'ignore'] });
    let buf = '';
    let done = false;
    const finish = (v) => { if (!done) { done = true; clearTimeout(timer); p.kill(); resolve(v); } };
    const timer = setTimeout(() => finish('timeout'), 180000);
    p.stdout.on('data', (c) => {
      buf += c;
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const l of lines) {
        let ev;
        try { ev = JSON.parse(l); } catch (e) { continue; }
        const blocks = (ev.type === 'assistant' && ev.message && ev.message.content) || [];
        for (const b of blocks) {
          if (b.type === 'tool_use' && b.name === 'Skill') return finish(String(b.input.skill).replace(/^.*:/, ''));
        }
        // A failed run (rate limit, auth, crash) is not a routing decision; counting it as none
        // fails every expected row and falsely passes every none row.
        if (ev.type === 'result') return finish(ev.is_error ? 'error' : 'none');
      }
    });
    p.on('close', () => finish('error'));
    p.on('error', () => finish('error'));
  });
}

(async () => {
  const per = {};
  const fails = {};
  let pass = 0;
  for (const [prompt, exp] of rows) {
    const got = await routed(prompt, exp);
    const ok = got === exp;
    const s = per[exp] || (per[exp] = { pass: 0, n: 0 });
    s.n++;
    if (ok) { s.pass++; pass++; } else { fails[prompt] = got; console.log(`FAIL expected=${exp} got=${got}: ${prompt}`); }
  }
  for (const k of Object.keys(per).sort()) console.log(`${k}\t${per[k].pass}/${per[k].n}`);
  const rate = rows.length ? (100 * pass) / rows.length : 0;
  console.log(`overall ${pass}/${rows.length} = ${rate.toFixed(1)}%`);
  const errors = Object.values(fails).filter((g) => g === 'error' || g === 'timeout').length;
  if (errors) console.log(`${errors} run(s) errored or timed out; their rows are not routing results`);
  for (const d of Object.values(cwds)) fs.rmSync(d, { recursive: true, force: true });
  process.exit(rate < min ? 1 : 0);
})();
