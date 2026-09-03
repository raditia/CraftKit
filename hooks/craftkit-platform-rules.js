#!/usr/bin/env node
// CraftKit SessionStart hook: loads platform-scoped rules only in a matching project.
// Claude Code has no user-scope path-scoped rule mechanism. `.claude/rules/*.md` with
// `paths:` is project-scoped and checked in, while craftkit ships rules at user scope, so a
// rule in the managed CLAUDE.md block loads in EVERY project. fe-rules therefore taught
// EVPMR laws while the session worked on Kotlin, where they are wrong by definition.
// A rule declaring `platform: fe` is left OUT of the managed block by adapters/claude.sh and
// arrives here instead, injected once per session when the cwd matches.
// SessionStart, not UserPromptSubmit: this body is ~1k tokens, and per-prompt injection would
// re-add it every turn. SessionStart also fires on resume, clear, and compact, so the rules
// come back after a context reset rather than silently vanishing mid-session.
// Escape hatch: CRAFTKIT_GATE=off.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { detectPlatform } = require(path.join(__dirname, 'craftkit-platform.js'));

// Where adapters/claude.sh stages installed rules. Platform-scoped ones stay here and are
// deliberately absent from ~/.claude/CLAUDE.md.
const STAGE = path.join(os.homedir(), '.craftkit', 'claude-rules');

// Offset of the closing --- fence, or -1 when there is no leading frontmatter block. Both
// readers below derive from this, so they can't disagree on where frontmatter ends.
function frontmatterEnd(text) {
  return text.startsWith('---') ? text.indexOf('\n---', 3) : -1;
}

// Reads one frontmatter field from the leading --- block. Same shape the adapters parse, so
// a rule the shell skipped is the rule this picks up.
function field(text, name) {
  const end = frontmatterEnd(text);
  if (end < 0) return '';
  const m = text.slice(3, end).match(new RegExp('^' + name + ':[ \\t]*(.+)$', 'm'));
  return m ? m[1].trim() : '';
}

function stripFrontmatter(text) {
  const end = frontmatterEnd(text);
  return end < 0 ? text : text.slice(end + 4).replace(/^\n+/, '');
}

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_GATE === 'off') return pass();

  let payload = {};
  try { payload = JSON.parse(input); } catch (e) { /* cwd falls back below */ }
  const cwd = payload.cwd || process.cwd();

  const keys = detectPlatform(cwd).keys;
  if (!keys.length) return pass();

  let files;
  try { files = fs.readdirSync(STAGE).filter(n => /\.md$/i.test(n)).sort(); } catch (e) { return pass(); }

  const bodies = [];
  const names = [];
  for (const f of files) {
    let text;
    try { text = fs.readFileSync(path.join(STAGE, f), 'utf8'); } catch (e) { continue; }
    const want = field(text, 'platform');
    if (!want) continue;
    // Comma-separated, so one rule can cover several platforms.
    const wanted = want.split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
    if (!wanted.some(w => keys.includes(w))) continue;
    names.push(f.replace(/\.md$/i, ''));
    bodies.push(stripFrontmatter(text).trim());
  }
  if (!bodies.length) return pass();

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext:
        'CraftKit platform rules for this project (' + keys.join(' + ') + '), always-active here ' +
        'and deliberately absent in other platforms: ' + names.map(n => '`' + n + '`').join(', ') + '\n\n' +
        bodies.join('\n\n---\n\n')
    }
  }));
});
