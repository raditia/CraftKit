#!/usr/bin/env node
// Shared drift detector: has a file changed since the baseline a context doc was written
// against? Answers clean / drifted / cannot-verify, never guessing clean when it cannot see.
//
// ponytail: retained with no caller. ADR-0002 removed the stored context doc and with it the
// freshness check that called this, and ADR-0001 rejected it for intent (this repo squash-merges,
// so a recorded baseline is unreachable after merge and cannot-verify would be the common
// answer). Kept deliberately: the clean/drifted/cannot-verify distinction is the hard part and is
// tested by check.sh check 29, so re-deriving it later costs more than keeping it. Its previous
// consumer gate-stale-context.js no longer exists. remove: if nothing calls it by the time a
// third release needs a baseline comparison, delete it with check 29 and its README row.
//
// One `git diff --name-only <baseline> -- <paths>` does the whole job, rather than a
// hash-object/rev-parse pair per file: diff honors .gitattributes clean filters (a
// text=auto or LFS entry otherwise reports permanent false drift), covers the staged and
// worktree states together, and detects renames instead of fataling on the old path.
//
// Three outcomes, and cannot-verify is deliberately not clean. An unreachable baseline is
// the common case here, not an edge one: this repo squash-merges, so the commit a context
// doc recorded leaves reachable history as soon as its branch merges.

const { execFileSync } = require('child_process');

function git(cwd, args) {
  return execFileSync('git', ['-C', cwd].concat(args),
    { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] });
}

// 'clean' | 'drifted' | 'cannot-verify', plus the files that moved and why it could not tell.
function drift(cwd, baseline, paths) {
  if (!baseline) return { state: 'cannot-verify', reason: 'no baseline recorded', files: [] };

  try {
    git(cwd, ['rev-parse', '--is-inside-work-tree']);
  } catch (e) {
    return { state: 'cannot-verify', reason: 'not a git repository', files: [] };
  }

  // cat-file -e on the commit itself, because a baseline that has left reachable history
  // makes every later answer meaningless, and diff against it fails in a way that is easy
  // to mistake for "nothing changed".
  try {
    git(cwd, ['cat-file', '-e', baseline + '^{commit}']);
  } catch (e) {
    return {
      state: 'cannot-verify',
      reason: 'baseline ' + String(baseline).slice(0, 12) + ' is unreachable, so it was squashed, rebased, amended or collected',
      files: []
    };
  }

  let out;
  try {
    out = git(cwd, ['diff', '--name-only', baseline, '--'].concat(paths || []));
  } catch (e) {
    return { state: 'cannot-verify', reason: 'git diff failed against ' + String(baseline).slice(0, 12), files: [] };
  }

  const files = out.split('\n').map(s => s.trim()).filter(Boolean);
  return files.length
    ? { state: 'drifted', reason: files.length + ' file(s) changed since the baseline', files: files }
    : { state: 'clean', reason: 'no change since the baseline', files: [] };
}

module.exports = { drift };
