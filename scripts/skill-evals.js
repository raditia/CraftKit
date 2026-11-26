#!/usr/bin/env node
// On-demand routing eval. COSTS API CALLS: one `claude -p` run per row of evals/routing.tsv.
// Not run by check.sh or CI.
// Usage: node scripts/skill-evals.js [--skill NAME] [--limit N] [--min PCT]
// For each prompt it records the first Skill tool call the model makes (none when it makes
// no Skill call) and compares it with the expected column. Exits 1 when the overall pass
// rate is under --min (default 0, report only).
const fs = require('fs');
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

function routed(prompt) {
  return new Promise((resolve) => {
    const p = spawn('claude', ['-p', prompt, '--output-format', 'stream-json', '--verbose',
      '--disallowedTools', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Bash'], { stdio: ['ignore', 'pipe', 'ignore'] });
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
        if (ev.type === 'result') return finish('none');
      }
    });
    p.on('close', () => finish('none'));
    p.on('error', () => finish('error'));
  });
}

(async () => {
  const per = {};
  let pass = 0;
  for (const [prompt, exp] of rows) {
    const got = await routed(prompt);
    const ok = got === exp;
    const s = per[exp] || (per[exp] = { pass: 0, n: 0 });
    s.n++;
    if (ok) { s.pass++; pass++; } else console.log(`FAIL expected=${exp} got=${got}: ${prompt}`);
  }
  for (const k of Object.keys(per).sort()) console.log(`${k}\t${per[k].pass}/${per[k].n}`);
  const rate = rows.length ? (100 * pass) / rows.length : 0;
  console.log(`overall ${pass}/${rows.length} = ${rate.toFixed(1)}%`);
  process.exit(rate < min ? 1 : 0);
})();
