#!/usr/bin/env node
// CraftKit — UserPromptSubmit hook: enforce skill-first routing gate every turn.
// Installed by sync.sh via adapters/claude.sh. Fires unconditionally on every prompt.
// Kept terse on purpose — full routing table + descriptions live always-on in
// rules/using-agent-skills.md; this is the per-turn nudge, not a second copy of the table.
// NOTE: every skill in skills/ must appear here as /<name> or sync.sh's routing drift guard aborts.

const fs = require('fs');
const os = require('os');
const path = require('path');

// Model tier detection — reads the logged-in account from ~/.claude.json.
// Domain check first (gmail.com = personal), organizationType as fallback for
// non-Gmail personal accounts, personal as the safe default on any read/parse failure.
// See rules/using-agent-skills.md → "Model routing" for the full tier table.
function detectModelTier() {
  const PERSONAL = { label: 'personal', cheapest: 'claude-haiku-4-5', everyday: 'claude-sonnet-5', escalate: 'claude-opus-4-8' };
  const ENTERPRISE = { label: 'enterprise', cheapest: 'claude-sonnet-5', everyday: 'claude-opus-4-8', escalate: 'claude-fable-5' };
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8'));
    const oa = cfg.oauthAccount || {};
    const domain = String(oa.emailAddress || '').toLowerCase().split('@')[1] || '';
    if (domain === 'gmail.com' || domain === 'googlemail.com') return PERSONAL;
    const orgType = String(oa.organizationType || '').toLowerCase();
    if (orgType.includes('enterprise')) return ENTERPRISE;
    return PERSONAL;
  } catch (e) {
    return PERSONAL;
  }
}

// Platform detection — deterministic, so the model never infers RN/web vs Android vs iOS
// from filenames. Nearest ancestor holding a marker wins: from an RN root only package.json
// matches; from inside its android/ subdir build.gradle matches first, which is the right
// answer for native work there. Several markers at one level = mixed, report all.
const PLATFORM_MARKERS = [
  { label: 'Android (MVP)', match: n => /^(settings|build)\.gradle(\.kts)?$/.test(n) },
  { label: 'iOS (MVVM-C)', match: n => n === 'Package.swift' || n === 'Podfile' || /\.xc(odeproj|workspace)$/.test(n) },
  { label: 'React Native / web (EVPMR)', match: n => n === 'package.json' },
];

function detectPlatform(startDir) {
  let dir = startDir;
  for (let depth = 0; depth < 12; depth++) {
    let entries;
    try {
      entries = fs.readdirSync(dir);
    } catch (e) {
      return null;
    }
    const hits = PLATFORM_MARKERS.filter(p => entries.some(n => p.match(n))).map(p => p.label);
    if (hits.length) return hits.join(' + ');
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
  return null;
}

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  const tier = detectModelTier();
  let cwd = process.cwd();
  try {
    const payload = JSON.parse(input);
    if (payload && typeof payload.cwd === 'string') cwd = payload.cwd;
  } catch (e) { /* no cwd in payload — process.cwd() stands */ }
  const platform = detectPlatform(cwd);
  const platformLine = platform
    ? `Platform (detected from cwd, authoritative): ${platform}. Route to this platform's skills, agents, and gates.\n\n`
    : '';
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext:
        "CraftKit skill-first gate. Classify every prompt against skills BEFORE responding; on match output 'Running /skill [tier] — reason.' then invoke, else output exactly 'No skill matched for this request. Responding directly.' Do NOT respond before invoking. Silent bypass = violation. Full routing table + tiebreakers: rules/using-agent-skills.md.\n\n" +
        platformLine +
        "Orchestrators: build/implement feature→/parallel-build · review/check changes→/parallel-review · ship/merge→/parallel-ship · broken/bug/crash→/fix · tests/coverage→platform test skill (/fe-test RN-web · /android-test · /ios-test) · PR message→/pr-message · scaffold only→/build\n" +
        "Skills (RN/web EVPMR): /fe-context /fe-scaffold /fe-review /fe-patterns /fe-a11y /fe-performance /fe-test /code-quality /debug /ideate /think /ponytail-review /ponytail-audit /ponytail-debt\n" +
        "Planning (opt-in): /define chains interview→spec→plan (checkpoint-gated) — use for 'plan this feature' / 'spec before building'. Or invoke a phase alone: /interview (de-fuzz) · /spec (PRD) · /plan (tasks) · /adr (decision record) · /docs (dual-audience humanized docs). adr+docs also offered as tail of /parallel-ship. Never auto-run from /parallel-build.\n" +
        "General: /grill (stress-test existing plan/decision — frontier-round interview; 'grill'/'poke holes'/'stress-test') · /research (primary-source research note, background agent) · /handoff (compact session into handoff doc for fresh agent)\n" +
        "Android (*.kt/*.java, MVP): /android-patterns /android-scaffold /android-review /android-test /android-a11y /android-performance /android-context\n" +
        "iOS (*.swift/*.m, MVVM-C): /ios-patterns /ios-scaffold /ios-review /ios-test /ios-a11y /ios-performance /ios-context\n" +
        "Every orchestrator is platform-routed — /parallel-build /parallel-review /parallel-ship /build /fix /ship /pr-message detect RN-web vs Android vs iOS at Step 0 and swap in that platform's gates, skills, and agents. Native single-screen work uses no EVPMR and no docs/context.md — read a real sibling screen instead; standard context loading does not apply there. Announcing a /fe-* skill on a .kt or .swift task is a routing error.\n\n" +
        `Model tier (detected from ~/.claude.json): ${tier.label} — cheapest=${tier.cheapest}, everyday=${tier.everyday}, escalate=${tier.escalate}. Use these for Claude Code rows in the Model routing table in rules/using-agent-skills.md.`
    }
  }));
});
