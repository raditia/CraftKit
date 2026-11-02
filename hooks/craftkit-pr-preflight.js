#!/usr/bin/env node
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

function git(cwd, args) {
  return execFileSync('git', ['-C', cwd, ...args], {
    encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore']
  }).trim();
}
function root(cwd) {
  return fs.realpathSync(git(cwd, ['rev-parse', '--show-toplevel']));
}
function recordPath(cwd) {
  const key = crypto.createHash('sha256').update(root(cwd)).digest('hex');
  return path.join(os.homedir(), '.craftkit-state', 'pr-preflight', key + '.json');
}
const text = value => typeof value === 'string' && value.trim().length > 0 &&
  !/^(TODO|TBD|placeholder|n\/a)$/i.test(value.trim());
function check(cwd, body, record) {
  try {
    if (!record || record.version !== 1) return 'Missing or invalid version 1 preflight record.';
    if (record.repository !== root(cwd)) return 'Preflight record belongs to another repository.';
    const head = git(cwd, ['rev-parse', 'HEAD']);
    if (record.head !== head) return 'Preflight record is stale: HEAD changed.';
    if (git(cwd, ['status', '--porcelain', '--untracked-files=no'])) return 'Commit tracked and staged changes before PR preflight.';
    if (!Array.isArray(record.checks) || !record.checks.length ||
        record.checks.some(c => !c || !text(c.name) || !['pass', 'blocked'].includes(c.result) || !text(c.details))) {
      return 'At least one check with a pass/blocked result and details is required.';
    }
    const review = record.review;
    if (!review || review.status !== 'pass' || !text(review.agent) || !text(review.summary)) {
      return 'A passing independent review with agent and summary is required.';
    }
    if (!Array.isArray(record.evidence) || !Array.isArray(record.limitations) ||
        record.limitations.some(l => !text(l))) return 'Evidence and limitations must be arrays.';
    if (record.checks.some(c => c.result === 'blocked' && !record.limitations.includes(c.details))) {
      return 'Every blocked check detail must be recorded verbatim as a validation limitation.';
    }
    if (!record.evidence.length && !record.limitations.length) return 'Provide evidence or document an incomplete validation limitation.';
    if (typeof body !== 'string' || !/^#{1,6}\s+Evidence\s*#*\s*$/im.test(body)) return 'PR body needs an Evidence heading.';
    for (const evidence of record.evidence) {
      if (!evidence || !['video', 'image', 'log', 'test'].includes(evidence.kind) ||
          evidence.verified !== true || evidence.revision !== head || !text(evidence.scenario)) {
        return 'Evidence needs kind, verified: true, current revision and scenario.';
      }
      let url;
      try { url = new URL(evidence.url); } catch (_) { return 'Evidence needs an HTTPS reviewer-accessible URL.'; }
      if (url.protocol !== 'https:' || url.username || url.password ||
          /^(localhost|127\.|\[::1\]|example\.(com|org|net)$)/i.test(url.hostname) ||
          /(?:placeholder|\bTODO\b|\bTBD\b|<|>|\.\.\.)/i.test(evidence.url)) return 'Evidence URL is local, insecure or a placeholder.';
      if (!body.includes(evidence.url)) return 'Every evidence URL must appear in the PR body.';
    }
    if (record.limitations.some(l => !body.includes(l))) return 'Every validation limitation must appear in the PR body.';
    return null;
  } catch (_) { return 'Cannot verify preflight: Git repository or HEAD is unavailable.'; }
}

function main(args) {
  if (args.includes('--help')) {
    console.log('Usage: node craftkit-pr-preflight.js (--record <json> | --check) --body <markdown>\n' +
      'Checks commit, clean tracked files, recorded checks, review and PR evidence/limitations.\n' +
      'Records bind to repository and HEAD. Limitations mean INCOMPLETE: draft PR only.\n' +
      'Review independence, test execution, media playback and reviewer access are self-reported, not mechanically proved.');
    return;
  }
  try {
    const bodyIndex = args.indexOf('--body');
    const recordIndex = args.indexOf('--record');
    if (bodyIndex < 0 || !args[bodyIndex + 1] || (recordIndex < 0) === !args.includes('--check') ||
        (recordIndex >= 0 && !args[recordIndex + 1])) throw new Error('Use --record <json> or --check, plus --body <markdown>.');
    const cwd = process.cwd();
    const destination = recordPath(cwd);
    const record = JSON.parse(fs.readFileSync(recordIndex >= 0 ? args[recordIndex + 1] : destination, 'utf8'));
    if (recordIndex >= 0 && record && record.repository === undefined) record.repository = root(cwd);
    const reason = check(cwd, fs.readFileSync(args[bodyIndex + 1], 'utf8'), record);
    if (reason) throw new Error(reason);
    if (recordIndex >= 0) {
      fs.mkdirSync(path.dirname(destination), { recursive: true, mode: 0o700 });
      fs.writeFileSync(destination, JSON.stringify(record, null, 2) + '\n', { mode: 0o600 });
      fs.chmodSync(destination, 0o600);
    }
    console.log(record.limitations.length ? 'INCOMPLETE: draft PR only; see PR Evidence limitations.' : 'READY');
    console.log('Recorded assertions only: review independence, execution, playback and access are not mechanically proved.');
  } catch (error) {
    console.error('PR preflight blocked: ' + error.message);
    process.exitCode = 1;
  }
}
module.exports = { check, recordPath };
if (require.main === module) main(process.argv.slice(2));
