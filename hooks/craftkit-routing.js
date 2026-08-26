#!/usr/bin/env node
// CraftKit UserPromptSubmit hook: enforce skill-first routing gate every turn.
// Installed by sync.sh via adapters/claude.sh. Fires unconditionally on every prompt.
// Kept terse on purpose: full routing table + descriptions live always-on in
// rules/using-agent-skills.md; this is the per-turn nudge, not a second copy of the table.
// NOTE: every skill in skills/ must appear here as /<name> or sync.sh's routing drift guard aborts.

const fs = require('fs');
const os = require('os');
const path = require('path');

// Model tier resolution, derived from what the account is actually entitled to,
// so a new model release needs no edit here. Claude Code caches the entitlement
// list in ~/.claude.json: `modelAccessCache` (every model, with an `entitled`
// flag) plus `additionalModelOptionsCache` (extra picker entries, which can be
// selectable while the base id still reads entitled:false, hence the union).
// Tiers are the top three available families, newest version of each. That
// reproduces both historical plan rows without asking which plan this is:
// no fable  -> haiku / sonnet / opus   (was "personal")
// has fable -> sonnet / opus  / fable  (was "enterprise")
// FAMILY_RANK is the one line a genuinely NEW family name needs: a name alone
// cannot say where it sits. Version bumps inside a known family are automatic.
const FAMILY_RANK = ['haiku', 'sonnet', 'opus', 'fable'];

// Plan decides the tier WINDOW, entitlements decide the concrete ids. Deriving the
// window from "top three families present" instead looked equivalent, since it reproduced
// both plan rows, but it rode on fable being absent from personal accounts, and the
// signal it actually read is additionalModelOptionsCache, a picker list rather than an
// access list. Advertise fable to a Pro account (upsell, trial) and its everyday tier
// silently jumps to opus. So personal plans cap below the frontier family: everyday
// stays sonnet no matter what the picker shows. The ids inside the window still come
// from entitlements, which is what keeps a release from needing an edit here.
const PERSONAL_CAP = 'opus';

// Aliases are what the Agent tool's `model:` accepts, and they self-update to the
// newest model in the family, so a spawn should carry the alias and the concrete
// id is only ever shown to the user.
const FALLBACK = { plan: 'personal', cheapest: 'haiku', everyday: 'sonnet', escalate: 'opus', resolved: false };

// Enterprise is the only plan that routes to the frontier family, so anything
// unreadable or unrecognized falls to personal, the more conservative window.
function detectPlan(oauthAccount) {
  const oa = oauthAccount || {};
  const domain = String(oa.emailAddress || '').toLowerCase().split('@')[1] || '';
  if (domain === 'gmail.com' || domain === 'googlemail.com') return 'personal';
  return String(oa.organizationType || '').toLowerCase().includes('enterprise') ? 'enterprise' : 'personal';
}

// claude-opus-4-8 -> [4,8] · claude-haiku-4-5-20251001 -> [4,5] (date segment ends it)
// claude-fable-5[1m] -> [5] · claude-3-opus-20240229 -> null (pre-family-first naming)
function parseModelId(raw) {
  const id = String(raw || '').replace(/\[.*$/, '');
  const m = id.match(new RegExp('^claude-(' + FAMILY_RANK.join('|') + ')-([\\d-]+)'));
  if (!m) return null;
  const version = [];
  for (const seg of m[2].split('-')) {
    if (!seg || seg.length >= 8) break;
    version.push(Number(seg));
  }
  return version.length ? { id, family: m[1], version } : null;
}

function newerVersion(a, b) {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const d = (a[i] || 0) - (b[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

function resolveModelTiers() {
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8'));
    const ids = (cfg.modelAccessCache || []).filter(m => m && m.entitled).map(m => m.apiName)
      .concat((cfg.additionalModelOptionsCache || []).map(m => m && m.value));
    const best = {};
    for (const raw of ids) {
      const p = parseModelId(raw);
      if (p && (!best[p.family] || newerVersion(p.version, best[p.family].version))) best[p.family] = p;
    }
    const plan = detectPlan(cfg.oauthAccount);
    const ceiling = plan === 'enterprise' ? FAMILY_RANK.length - 1 : FAMILY_RANK.indexOf(PERSONAL_CAP);
    const ladder = FAMILY_RANK.slice(0, ceiling + 1).filter(f => best[f]).map(f => best[f]);
    if (!ladder.length) return FALLBACK;
    const at = i => ladder[Math.max(0, ladder.length - i)];
    return { plan, cheapest: at(3).id, everyday: at(2).id, escalate: at(1).id, resolved: true };
  } catch (e) {
    return FALLBACK;
  }
}

// Platform detection: deterministic, so the model never infers RN/web vs Android vs iOS
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
  const tier = resolveModelTiers();
  let cwd = process.cwd();
  try {
    const payload = JSON.parse(input);
    if (payload && typeof payload.cwd === 'string') cwd = payload.cwd;
  } catch (e) { /* no cwd in payload; process.cwd() stands */ }
  const platform = detectPlatform(cwd);
  const platformLine = platform
    ? `Platform (detected from cwd, authoritative): ${platform}. Route to this platform's skills, agents, and gates.\n\n`
    : '';
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext:
        "CraftKit skill-first gate. Classify every prompt against skills BEFORE responding; on match output 'Running /skill [tier]: reason.' then invoke, else output exactly 'No skill matched for this request. Responding directly.' Do NOT respond before invoking. Silent bypass = violation. Full routing table + tiebreakers: rules/using-agent-skills.md.\n\n" +
        platformLine +
        "Orchestrators: build/implement feature→/parallel-build · review/check changes→/parallel-review · ship/merge→/parallel-ship · broken/bug/crash→/fix · tests/coverage→platform test skill (/fe-test RN-web · /android-test · /ios-test) · PR message→/pr-message · scaffold only→/build\n" +
        "Cannot spawn subagents (you are a subagent, or a session instruction disables spawning)? Take the sequential twin and proceed: /parallel-build→/build · /parallel-review→/review · /parallel-ship→/ship · /team-build→/build. Announce the command you ran, not the one you couldn't; state the substitution once if it costs a validation axis, then stop repeating it; the table sanctions the swap, so no conflict remains to surface.\n" +
        "Skills (RN/web EVPMR): /fe-context /fe-scaffold /fe-review /fe-patterns /fe-a11y /fe-performance /fe-test /code-quality /debug /ideate /think /ponytail-review /ponytail-audit /ponytail-debt\n" +
        "Planning (opt-in): /define chains interview→spec→plan (checkpoint-gated), use for 'plan this feature' / 'spec before building'. Or invoke a phase alone: /interview (de-fuzz) · /spec (PRD) · /plan (tasks) · /adr (decision record) · /docs (dual-audience humanized docs). adr+docs also offered as tail of /parallel-ship. Never auto-run from /parallel-build.\n" +
        "General: /grill (stress-test existing plan/decision via frontier-round interview; 'grill'/'poke holes'/'stress-test') · /research (primary-source research note, background agent) · /handoff (compact session into handoff doc for fresh agent)\n" +
        "Android (*.kt/*.java, MVP): /android-patterns /android-scaffold /android-review /android-test /android-a11y /android-performance /android-context\n" +
        "iOS (*.swift/*.m, MVVM-C): /ios-patterns /ios-scaffold /ios-review /ios-test /ios-a11y /ios-performance /ios-context\n" +
        "Every orchestrator is platform-routed: /parallel-build /parallel-review /parallel-ship /build /fix /ship /pr-message detect RN-web vs Android vs iOS at Step 0 and swap in that platform's gates, skills, and agents. Native single-screen work uses no EVPMR and no docs/context.md, so read a real sibling screen instead; standard context loading does not apply there. Announcing a /fe-* skill on a .kt or .swift task is a routing error.\n\n" +
        `Model tiers (${tier.plan} plan, ids resolved from ~/.claude.json entitlements): cheapest=${tier.cheapest}, everyday=${tier.everyday}, escalate=${tier.escalate}${tier.resolved ? '' : ' (entitlements unreadable, family aliases only)'}. These are authoritative: use them wherever a skill names a tier, and spawn agents with the family alias (haiku/sonnet/opus/fable), which tracks the newest model in that family on its own.`
    }
  }));
});
