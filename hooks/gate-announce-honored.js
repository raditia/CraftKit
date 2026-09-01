#!/usr/bin/env node
// CraftKit Stop gate: a turn that announced a skill cannot end without having invoked it.
// The other two gates key on code edits, so a turn producing only prose (a PR message, a
// humanized draft) passes both while the agent hand-rolls what the skill prescribes. That
// is the worse failure of the two: announcing and not running actively misleads, because
// the announcement reads as evidence the skill ran.
// Blocks at most once per stop attempt (stop_hook_active), so there is no loop.
// Escape hatch: CRAFTKIT_GATE=off.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { currentTurn } = require(path.join(__dirname, 'craftkit-transcript.js'));

// Line-anchored on purpose. Prose that merely mentions the announce format wraps it in
// backticks or buries it mid-sentence, so requiring the line to START with the verb keeps
// meta-discussion about the gate from tripping the gate.
const ANNOUNCE = /^[ \t]*(?:Running|Invoking)[ \t]+\/([A-Za-z0-9:_-]+)/gm;

const norm = s => String(s || '').replace(/^\//, '').toLowerCase();

function namesIn(dir, kind) {
  const out = [];
  let items;
  try { items = fs.readdirSync(dir); } catch (e) { return out; }
  for (const name of items) {
    // statSync follows symlinks; a marketplace-installed skill is a link, not a directory.
    let st;
    try { st = fs.statSync(path.join(dir, name)); } catch (e) { continue; }
    if (kind === 'skill' && st.isDirectory()) out.push(name);
    if (kind === 'command' && st.isFile() && /\.md$/i.test(name)) out.push(name.replace(/\.md$/i, ''));
  }
  return out;
}

// Only a name that resolves to something installed is enforced. An unresolvable name is
// most likely prose, a plugin skill this cannot see, or a typo, and a gate that guesses is
// worse than one that abstains.
// ponytail: plugin skills (<plugin>:<name>) live under ~/.claude/plugins and are not
// enumerated, so announcing one and skipping it goes uncaught. ceiling: plugin-heavy
// setups. upgrade: walk plugins/*/skills when that becomes a real miss.
function installed(cwd) {
  const roots = [path.join(os.homedir(), '.claude'), path.join(cwd, '.claude')];
  const set = new Set();
  for (const r of roots) {
    for (const n of namesIn(path.join(r, 'skills'), 'skill')) set.add(norm(n));
    for (const n of namesIn(path.join(r, 'commands'), 'command')) set.add(norm(n));
  }
  return set;
}

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_GATE === 'off') return pass();

  let payload;
  try { payload = JSON.parse(input); } catch (e) { return pass(); }
  if (payload.stop_hook_active) return pass();
  if (!payload.transcript_path) return pass();

  const turn = currentTurn(payload.transcript_path);
  if (!turn.readable) return pass();
  // A subagent does not announce; the parent turn is where routing is claimed.
  if (turn.sidechain) return pass();

  const known = installed(payload.cwd || process.cwd());
  const invoked = new Set(turn.skills.concat(turn.slashCommands).map(norm));

  const missing = [];
  // A fenced example is documentation, not a claim about this turn.
  const text = String(turn.assistantText || '').replace(/```[\s\S]*?```/g, '');
  let m;
  ANNOUNCE.lastIndex = 0;
  while ((m = ANNOUNCE.exec(text)) !== null) {
    const name = norm(m[1]);
    if (!known.has(name)) continue;
    if (invoked.has(name)) continue;
    if (!missing.includes(name)) missing.push(name);
  }
  if (!missing.length) return pass();

  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason:
      'Announced but never invoked: ' + missing.map(n => '/' + n).join(', ') + '\n' +
      'Announcing a skill is not invoking it, and the announcement reads as evidence it ran.\n' +
      'Call the Skill tool for each, then redo the work to the skill\'s actual template. ' +
      'If a skill no longer applies, retract the announcement in your reply instead of leaving it standing.' +
      (invoked.size ? '\nInvoked this turn: ' + Array.from(invoked).map(n => '/' + n).join(', ') : '')
  }));
});
