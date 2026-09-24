#!/usr/bin/env bash
# Content integrity checks for craftkit source. There is no build or test suite here, so
# the product is markdown, so this is the only thing standing between an authoring slip
# and every synced tool inheriting it. Every check below exists because the bug it
# catches actually shipped and sat undetected.
set -uo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || [[ "${BASH_VERSINFO[0]}" -eq 3 && "${BASH_VERSINFO[1]}" -lt 2 ]]; then
    echo "Error: bash 3.2+ required (got ${BASH_VERSION})"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_DIR="$REPO_DIR/rules"
PARTIALS_DIR="$REPO_DIR/partials"
SKILLS_DIR="$REPO_DIR/skills"
COMMANDS_DIR="$REPO_DIR/commands"
AGENTS_DIR="$REPO_DIR/agents"
HOOK="$REPO_DIR/hooks/craftkit-routing.js"
README="$REPO_DIR/README.md"
CHANGELOG="$REPO_DIR/CHANGELOG.md"

FAILURES=0
CURRENT=""

check() {
    CURRENT="$1"
    echo "==> $1"
}

fail() {
    echo "    FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

pass() {
    echo "    ok"
}

skill_names() { ls -d "$SKILLS_DIR"/*/ 2>/dev/null | xargs -n1 basename | sort; }
agent_names() { ls "$AGENTS_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort; }
command_names() { ls "$COMMANDS_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort; }
rule_names() { ls "$RULES_DIR"/*.md 2>/dev/null | xargs -n1 basename | sed 's/\.md$//' | sort; }

# ---------------------------------------------------------------------------
# 1. Every subagent_type reference resolves to a real agent file.
#    Renaming an agent without updating its callers leaves a command spawning
#    a subagent that does not exist, and the orchestrator degrades silently.
# ---------------------------------------------------------------------------
check "subagent_type references resolve"
_refs="$(grep -rhno 'subagent_type: "[a-z0-9-]*"' "$COMMANDS_DIR" "$SKILLS_DIR" 2>/dev/null \
    | sed 's/.*"\(.*\)"/\1/' | sort -u)"
if [[ -z "$_refs" ]]; then
    pass
else
    _missing=0
    for r in $_refs; do
        if [[ ! -f "$AGENTS_DIR/${r}.md" ]]; then
            fail "subagent_type \"$r\" has no agents/${r}.md"
            _missing=1
        fi
    done
    [[ $_missing -eq 0 ]] && pass
fi

# ---------------------------------------------------------------------------
# 2. No skill/command install-destination collision.
#    A skill with alwaysApply:false installs to the same path a command does
#    (adapters/claude.sh). Both passes then write the same file every sync and
#    the winner is decided by pass order, not intent. This is how a 7-line stub
#    shadowed a 137-line command for two years.
# ---------------------------------------------------------------------------
check "no skill/command dest collision"
_collide=0
for s in $(skill_names); do
    if [[ -f "$COMMANDS_DIR/${s}.md" ]] && ! grep -q "^alwaysApply: true" "$SKILLS_DIR/$s/SKILL.md" 2>/dev/null; then
        fail "skills/$s/ and commands/${s}.md both install to <tool>/commands/${s}.md, delete one"
        _collide=1
    fi
done
[[ $_collide -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 3. skills/ is exactly one level deep.
#    sync.sh globs skills/*/ and uses basename as the skill name; a nested
#    skills/group/name/ is silently never synced.
# ---------------------------------------------------------------------------
check "skills/ is flat"
_nested="$(find "$SKILLS_DIR" -mindepth 3 -name SKILL.md 2>/dev/null)"
if [[ -n "$_nested" ]]; then
    echo "$_nested" | while IFS= read -r n; do echo "    FAIL: nested skill never syncs: ${n#$REPO_DIR/}"; done
    FAILURES=$((FAILURES + 1))
else
    pass
fi

# ---------------------------------------------------------------------------
# 4. Frontmatter is present and its name matches the filename.
#    A name/filename mismatch installs under one name and routes under another.
# ---------------------------------------------------------------------------
check "frontmatter name matches path"
_fm=0
for s in $(skill_names); do
    _n="$(awk 'NR>1 && /^---$/{exit} /^name:/{sub(/^name:[[:space:]]*/,"");print;exit}' "$SKILLS_DIR/$s/SKILL.md")"
    [[ "$_n" == "$s" ]] || { fail "skills/$s/SKILL.md declares name: '${_n:-<missing>}'"; _fm=1; }
done
for a in $(agent_names); do
    _n="$(awk 'NR>1 && /^---$/{exit} /^name:/{sub(/^name:[[:space:]]*/,"");print;exit}' "$AGENTS_DIR/$a.md")"
    [[ "$_n" == "$a" ]] || { fail "agents/$a.md declares name: '${_n:-<missing>}'"; _fm=1; }
    grep -q "^description:" "$AGENTS_DIR/$a.md" || { fail "agents/$a.md has no description"; _fm=1; }
    grep -q "^model:" "$AGENTS_DIR/$a.md" || { fail "agents/$a.md has no model"; _fm=1; }
done
[[ $_fm -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 5. Every craftkitInject name resolves, and the field itself is spelled right.
#    Covers agents AND commands: both are rendered by the same splice, so both
#    fail the same way. An injecting agent whose source is renamed loses its whole
#    checklist and still installs: a review agent with nothing to review by. An
#    injecting command loses its procedure and still installs, so an orchestrator
#    reaches Phase 2 with no classifier. Also flags a partial nothing injects,
#    which is dead weight that no sync would ever surface.
#    The target half of this check greps `^craftkitInject:`, so a misspelled
#    FIELD passes vacuously: awk finds no list, the loop is skipped, and the
#    agent installs with no injected body at all. fe-review would then review
#    without the EVPMR constraints it exists to enforce, silently. Any
#    frontmatter key that mentions inject but is not exactly craftkitInject is
#    therefore a failure, which is cheaper than inferring intent.
# ---------------------------------------------------------------------------
check "craftkitInject sources resolve"
_inj=0
_inj_used=""
_inj_scan() {
    # $1 = label for failures, $2 = file
    local label="$1" f="$2" bad list n
    bad="$(awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^[A-Za-z_-]+:/{k=$0; sub(/:.*/,"",k); if (k ~ /[Ii]nject/ && k != "craftkitInject") print k}' "$f")"
    if [[ -n "$bad" ]]; then
        fail "$label frontmatter key '$bad' looks like craftkitInject but is not, so the inject is skipped silently"
        _inj=1
    fi
    list="$(awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^craftkitInject:/{sub(/^craftkitInject:[[:space:]]*/,"");print;exit}' "$f")"
    [[ -z "$list" ]] && return
    for n in $(echo "$list" | tr ',' ' '); do
        _inj_used="$_inj_used $n"
        if [[ ! -f "$PARTIALS_DIR/${n}.md" && ! -f "$RULES_DIR/${n}.md" && ! -f "$SKILLS_DIR/${n}/SKILL.md" ]]; then
            fail "$label injects '$n', which is not in partials/, rules/ or skills/"
            _inj=1
        fi
    done
}
for c in "$REPO_DIR"/commands/*.md; do
    [[ -f "$c" ]] && _inj_scan "commands/$(basename "$c")" "$c"
done
# Agents are an injection host too (adapters/claude.sh has effective_claude_agent_source for
# exactly that), and scanning only commands/ meant an agent's inject was never validated AND
# a partial used only by agents reported as used by nothing. Found by a partial that 14
# agents injected.
for a in "$REPO_DIR"/agents/*.md; do
    [[ -f "$a" ]] && _inj_scan "agents/$(basename "$a")" "$a"
done
# Skills joined the host list in v1.37.0 (the skills pass renders for every adapter). An
# unscanned host is the same vacuous pass as before: the skill installs with its core
# section simply absent, and no sync reports it.
for _s in "$SKILLS_DIR"/*/SKILL.md; do
    [[ -f "$_s" ]] && _inj_scan "skills/$(basename "$(dirname "$_s")")/SKILL.md" "$_s"
done
for _p in "$PARTIALS_DIR"/*.md; do
    [[ -f "$_p" ]] || continue
    _pn="$(basename "$_p" .md)"
    case " $_inj_used " in
        *" $_pn "*) ;;
        *) fail "partials/$_pn.md is injected by nothing, so it ships to no tool and no sync reports it"; _inj=1 ;;
    esac
done
for a in $(agent_names); do
    # The scanner checks the misspelled-field case BEFORE the empty-list skip on
    # purpose: a misspelled field is exactly what leaves the list empty.
    _inj_scan "agents/$a.md" "$AGENTS_DIR/$a.md"
done
[[ $_inj -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 6. Routing hook names only things that exist.
#    sync.sh already guards skills -> hook. This is the reverse: a rename leaves
#    the hook advertising a slash command that resolves to nothing.
#    Scoped to unambiguous platform-prefixed names to stay quiet on prose.
# ---------------------------------------------------------------------------
check "routing hook targets exist"
_hookrefs="$(grep -o '/\(fe\|android\|ios\|ponytail\|parallel\)-[a-z0-9]*' "$HOOK" 2>/dev/null \
    | sed 's|^/||' | sort -u)"
_hk=0
for n in $_hookrefs; do
    # bare prefix (from prose like "/fe-*") carries no target to verify
    case "$n" in fe-|android-|ios-|ponytail-|parallel-) continue ;; esac
    if [[ ! -d "$SKILLS_DIR/$n" && ! -f "$COMMANDS_DIR/${n}.md" ]]; then
        fail "hook advertises /$n, but no such skill or command"
        _hk=1
    fi
done
[[ $_hk -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 7. Platform coverage: a command that routes to fe-* must also route native.
#    The three parallel commands hardcoded fe-* agents and tsc/jest gates, so a
#    .kt or .swift branch got the wrong gates and no matching reviewer.
#    Exempt: commands that are platform-agnostic by construction.
# ---------------------------------------------------------------------------
check "orchestrators cover all platforms"
_exempt_platform="define"   # pre-code planning only, no platform surface
_pc=0
for c in $(command_names); do
    case " $_exempt_platform " in *" $c "*) continue ;; esac
    _f="$COMMANDS_DIR/${c}.md"
    grep -q "fe-" "$_f" || continue
    if ! grep -q "android-" "$_f" || ! grep -q "ios-" "$_f"; then
        fail "commands/${c}.md routes to fe-* but not both android-* and ios-*"
        _pc=1
    fi
done
[[ $_pc -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 8. The native opt-out is declared where a reader will see it. ADR-0002 left
#    the always-on rule describing a derived-context step; native single-screen
#    skills take no such step, and an always-on rule that forgot to say so
#    contradicts them on every native turn. The old form of this check grepped
#    rules/ for an absolute docs/context.md claim, which stopped being reachable
#    the moment that filename left the rule, so it is replaced rather than kept
#    as a gate that cannot fail.
# ---------------------------------------------------------------------------
check "native skills declare the derived-context opt-out"
_no=0
grep -q "native skills only on multi-screen branches" "$REPO_DIR/rules/using-agent-skills.md" \
    || { fail "the always-on loading procedure lost its native scope caveat, so it now claims a derived-context step on native single-screen turns"; _no=1; }
_optout=0
for _f in "$SKILLS_DIR"/android-*/SKILL.md "$SKILLS_DIR"/ios-*/SKILL.md; do
    grep -q "No derived-context step" "$_f" && _optout=$((_optout + 1))
done
# Ten of the twelve native skills are single-screen; the two context generators opt in.
[[ $_optout -ge 10 ]] \
    || { fail "only $_optout native skills declare the derived-context opt-out, want >= 10, so some now inherit a step they do not take"; _no=1; }
[[ $_no -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 9. README lists every agent and skill (authoring rule #3).
#    The reference tables are the only index a reader has; a missing row means a
#    file nobody knows exists.
# ---------------------------------------------------------------------------
check "README documents every agent and skill"
_doc=0
for a in $(agent_names); do
    grep -q "agents/$a.md" "$README" || { fail "agents/$a.md has no README row"; _doc=1; }
done
for s in $(skill_names); do
    grep -q "skills/$s/SKILL.md" "$README" || { fail "skills/$s/ has no README row"; _doc=1; }
done
# Rules were never covered here, so a rule could ship, or lose its row, unnoticed. Found
# when an acceptance criterion claiming "check.sh covers it" turned out to be false: the
# rule had a row by luck, not because anything held it there.
for r in "$RULES_DIR"/*.md; do
    _r="$(basename "$r" .md)"
    grep -q "rules/$_r.md" "$README" || { fail "rules/$_r.md has no README row"; _doc=1; }
done
[[ $_doc -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 10. Version agreement: package.json, README header, newest CHANGELOG.md section.
#     The release workflow reads the version from the README header and the release
#     notes from the matching CHANGELOG.md section, so a mismatch either ships the
#     wrong number or aborts the release. Both files, one number.
# ---------------------------------------------------------------------------
check "version is consistent"
_pkg="$(awk -F'"' '/"version":/{print $4;exit}' "$REPO_DIR/package.json")"
_hdr="$(awk '/^# craftkit/{gsub(/[`v]/,"");print $3;exit}' "$README")"
_log="$(awk '/^## v[0-9]/{print $2;exit}' "$CHANGELOG" | tr -d 'v')"
if [[ "$_pkg" == "$_hdr" && "$_pkg" == "$_log" ]]; then
    pass
else
    fail "package.json=$_pkg  README header=$_hdr  CHANGELOG.md newest=$_log, must match"
fi

# ---------------------------------------------------------------------------
# 11. Routing hook resolves each platform from cwd, and survives bad stdin.
#     Platform used to be the model's job to infer from filenames, which is how
#     a /fe-* skill got announced on a .kt task. It is now injected per prompt,
#     but a marker typo or a crash on malformed stdin removes the whole gate
#     silently, since a dead UserPromptSubmit hook just yields no context.
#     Behavioral on purpose: a grep would pass on detection that never fires.
# ---------------------------------------------------------------------------
check "routing hook detects platform from cwd"
if ! command -v node >/dev/null 2>&1; then
    echo "    skipped (node not on PATH)"
else
    _fx="$(mktemp -d)"
    mkdir -p "$_fx/a" "$_fx/i" "$_fx/w"
    touch "$_fx/a/settings.gradle" "$_fx/i/Podfile" "$_fx/w/package.json"
    _probe() { echo "{\"cwd\":\"$1\"}" | node "$HOOK" 2>/dev/null; }
    _pd=0
    _probe "$_fx/a" | grep -q "Platform (detected from cwd, authoritative): Android (MVP)" \
        || { fail "settings.gradle did not resolve to Android"; _pd=1; }
    _probe "$_fx/i" | grep -q "Platform (detected from cwd, authoritative): iOS (MVVM-C)" \
        || { fail "Podfile did not resolve to iOS"; _pd=1; }
    _probe "$_fx/w" | grep -q "Platform (detected from cwd, authoritative): React Native / web (EVPMR)" \
        || { fail "package.json did not resolve to React Native / web"; _pd=1; }
    echo 'not json' | node "$HOOK" >/dev/null 2>&1 \
        || { fail "hook exits non-zero on malformed stdin, so the gate disappears every prompt"; _pd=1; }
    rm -rf "$_fx"
    [[ $_pd -eq 0 ]] && pass
fi

# ---------------------------------------------------------------------------
# 12. Every hook command ensure_tools registers resolves under a stripped PATH.
#     Hooks spawn with /usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:. so there is no homebrew,
#     no fnm, and a bare `rtk hook claude` died with "rtk: command not found".
#     Non-blocking, so it degraded silently: every Bash call ran unrewritten and
#     the whole token filter was off with nothing but a dim hook error to show it.
#     `rtk init` rewrites the entry to bare on each run, hence the re-absolutize.
# ---------------------------------------------------------------------------
check "rtk hook is absolutized after rtk init"
if ! grep -q '_rtk_hook_absolutize$' sync.sh; then
    fail "ensure_tools does not call _rtk_hook_absolutize, so bare 'rtk hook claude' fails under the hooks' stripped PATH"
elif ! grep -q '_rtk_hook_absolutize()' sync.sh; then
    fail "_rtk_hook_absolutize is called but never defined"
else
    pass
fi

# ---------------------------------------------------------------------------
# 13. Every name in ADAPTERS has a sourced adapter file, and every adapter file is
#     listed. sync.sh calls adapter functions by string interpolation, so a name with
#     no sourced file dies at the first call, mid-sync, after some tools are already
#     written. The reverse direction catches the other half: an adapter left on disk
#     but absent from ADAPTERS is dead weight that reads as a supported tool.
# ---------------------------------------------------------------------------
check "adapter arrays resolve"
_live="$(grep '^ADAPTERS=' "$REPO_DIR/sync.sh" | sed 's/[^(]*(//;s/).*//;s/"//g')"
_ad=0
[[ -n "$_live" ]] || { fail "ADAPTERS not found in sync.sh"; _ad=1; }
for a in $_live; do
    [[ -f "$REPO_DIR/adapters/${a}.sh" ]] || { fail "adapter '$a' listed but adapters/${a}.sh missing"; _ad=1; }
    grep -q "adapters/${a}.sh" "$REPO_DIR/sync.sh" || { fail "adapter '$a' listed but never sourced in sync.sh"; _ad=1; }
done
for _f in "$REPO_DIR"/adapters/*.sh; do
    _an="$(basename "$_f" .sh)"
    case " $_live " in *" $_an "*) ;; *) fail "adapters/${_an}.sh exists but is not in ADAPTERS, so delete it or list it"; _ad=1 ;; esac
done
[[ $_ad -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 14. The routing hook's node path is absolute and not version-pinned.
#     Hooks spawn under a stripped PATH with no profile, so the command must carry an
#     absolute interpreter, and it must be one that survives, because a dead
#     UserPromptSubmit hook silently removes the whole routing gate. A pinned
#     fnm/node-versions/<v> path is one `fnm uninstall` away from exactly that.
# ---------------------------------------------------------------------------
check "routing hook interpreter is durable"
if [[ ! -x /opt/homebrew/bin/node && ! -x /usr/local/bin/node ]]; then
    echo "    skipped (no package-manager node to prefer on this machine)"
else
    _nb="$(. "$REPO_DIR/adapters/claude.sh" >/dev/null 2>&1; _resolve_node_bin)"
    case "$_nb" in
        *fnm/node-versions*|*fnm_multishells*)
            fail "_resolve_node_bin returned version-pinned '$_nb' while a managed node exists" ;;
        /*) pass ;;
        *)  fail "_resolve_node_bin returned non-absolute '$_nb', but hooks get a stripped PATH" ;;
    esac
fi

# ---------------------------------------------------------------------------
# 15. Every parallel-* orchestrator has a sequential twin, named in both channels.
#     A parallel-* command exists to spawn agents, so a context that cannot spawn
#     them cannot run one: a subagent, or a session that disables spawning. With
#     no sanctioned substitute the routing gate forces a choice between violating
#     itself and narrating the conflict on every single turn, which is what it did.
#     Checked in the rule AND the hook because they duplicate this table by design.
# ---------------------------------------------------------------------------
check "parallel orchestrators have sequential twins"
_tw=0
for _p in "$COMMANDS_DIR"/parallel-*.md; do
    [[ -f "$_p" ]] || continue
    _pn="$(basename "$_p" .md)"
    _twin="${_pn#parallel-}"
    [[ -f "$COMMANDS_DIR/${_twin}.md" ]] \
        || { fail "/$_pn has no sequential twin commands/${_twin}.md to fall back to"; _tw=1; }
    grep -qE "/${_pn}[^A-Za-z0-9-].*/${_twin}([^A-Za-z0-9-]|\$)" "$RULES_DIR/using-agent-skills.md" \
        || { fail "using-agent-skills.md does not map /$_pn -> /$_twin for no-spawn contexts"; _tw=1; }
    grep -q "/${_pn}→/${_twin}" "$HOOK" \
        || { fail "routing hook does not map /${_pn} -> /${_twin} for no-spawn contexts"; _tw=1; }
done
[[ $_tw -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 16. A declared license has license text behind it.
#     `package.json` said "license": "MIT" for 26 releases with no LICENSE file in
#     the repo, so npm advertised MIT while the grant existed nowhere, GitHub could
#     not detect it, and four MIT-licensed upstreams were adapted without the notice
#     their license requires. A license claim nobody can read is not a license.
# ---------------------------------------------------------------------------
check "declared license has license text"
_lic="$(awk -F'"' '/"license":/{print $4;exit}' "$REPO_DIR/package.json")"
_licfile=""
for _c in LICENSE LICENSE.md LICENCE; do
    [[ -f "$REPO_DIR/$_c" ]] && { _licfile="$REPO_DIR/$_c"; break; }
done
if [[ -z "$_lic" ]]; then
    pass   # no claim made, nothing to back up
elif [[ -z "$_licfile" ]]; then
    fail "package.json declares \"license\": \"$_lic\" but no LICENSE file exists"
elif ! head -5 "$_licfile" | grep -qi -- "$_lic"; then
    # Header only, not the whole file: a third-party attribution block naming other
    # projects' licenses would otherwise satisfy this and hide a mismatched grant.
    fail "package.json declares '$_lic' but $(basename "$_licfile") does not name it in its header"
else
    pass
fi

# ---------------------------------------------------------------------------
# 17. Model tiers stay resolved, never written down. Every Claude release used to
#     mean editing ~17 files, and the ones missed silently routed work to a
#     retired model. Tiers now come from the hook's entitlement read, so a
#     versioned id in the content is a regression to that maintenance treadmill.
#     Aliases (sonnet/opus/..., Gemini CLI's pro/flash) are the sanctioned form.
#     All four vendors, not just Claude: the first cut of this check greped
#     `claude-*` only, which is how `codex-mini-latest` sat in the routing table
#     for six months after OpenAI retired it on 2026-02-12, the exact bug the
#     check exists to catch, missed because the guard was vendor-scoped.
# ---------------------------------------------------------------------------
check "content names model tiers, not versioned model ids"
_mid="$(grep -rEn 'claude-(haiku|sonnet|opus|fable)-[0-9]|gemini-[0-9]|\bgpt-[0-9]|codex-mini|\bo[13]\b' \
    "$REPO_DIR"/rules "$REPO_DIR"/skills "$REPO_DIR"/commands "$REPO_DIR"/agents 2>/dev/null || true)"
if [[ -n "$_mid" ]]; then
    fail "versioned model id in content, so name the tier instead and let the hook inject the id:"
    echo "$_mid" | sed 's/^/      /'
else
    pass
fi

# ---------------------------------------------------------------------------
# 18. The hook resolves the tier trio from entitlements. Behavioral: the whole
#     point is that a new release needs no edit, and a silent regression here
#     (bad parse, wrong rank) routes every skill to the wrong model with the
#     injected line still looking plausible. Fixtures cover both historical plan
#     shapes, a future version bump, and an unreadable config.
# ---------------------------------------------------------------------------
check "routing hook resolves model tiers from entitlements"
if ! command -v node >/dev/null 2>&1; then
    echo "    skipped (node not on PATH)"
else
    _fx="$(mktemp -d)"
    _tiers() { printf '%s' "$2" > "$_fx/.claude.json"; echo '{}' | HOME="$_fx" node "$HOOK" 2>/dev/null | tr ',' '\n' | grep -o "$1=[^ ,.\"]*" | head -1; }
    _M='{"apiName":"claude-haiku-4-5-20251001","entitled":true},{"apiName":"claude-sonnet-5","entitled":true},{"apiName":"claude-opus-5","entitled":true},{"apiName":"claude-fable-5","entitled":false}'
    _PICKER='"additionalModelOptionsCache":[{"value":"claude-fable-5[1m]"}]'
    _ENT='"oauthAccount":{"organizationType":"claude_enterprise"}'
    _PRO='"oauthAccount":{"emailAddress":"someone@gmail.com"}'
    _mt=0
    # Enterprise routes to the frontier family; everyday must be opus, not sonnet.
    [[ "$(_tiers everyday "{$_ENT,\"modelAccessCache\":[$_M],$_PICKER}")" == "everyday=claude-opus-5" ]] \
        || { fail "enterprise everyday is not opus"; _mt=1; }
    [[ "$(_tiers escalate "{$_ENT,\"modelAccessCache\":[$_M],$_PICKER}")" == "escalate=claude-fable-5" ]] \
        || { fail "picker-only fable ignored on enterprise, but additionalModelOptionsCache must count"; _mt=1; }
    # The regression this cap exists for: a personal plan shown fable in the picker
    # must still land everyday on sonnet. Deriving the window from "top three families
    # present" silently promoted it to opus, because the picker is a display list.
    [[ "$(_tiers everyday "{$_PRO,\"modelAccessCache\":[$_M],$_PICKER}")" == "everyday=claude-sonnet-5" ]] \
        || { fail "personal everyday is not sonnet, so fable in the picker promoted the window"; _mt=1; }
    [[ "$(_tiers cheapest "{$_PRO,\"modelAccessCache\":[$_M],$_PICKER}")" == "cheapest=claude-haiku-4-5-20251001" ]] \
        || { fail "personal cheapest is not haiku"; _mt=1; }
    # A version bump inside a known family must need no edit anywhere.
    [[ "$(_tiers everyday "{$_ENT,\"modelAccessCache\":[$_M,{\"apiName\":\"claude-opus-6-2\",\"entitled\":true}],$_PICKER}")" == "everyday=claude-opus-6-2" ]] \
        || { fail "newer version within a family did not win, so releases are not seamless"; _mt=1; }
    [[ "$(_tiers everyday 'not json')" == "everyday=sonnet" ]] \
        || { fail "unreadable entitlements did not fall back to family aliases"; _mt=1; }
    rm -rf "$_fx"
    [[ $_mt -eq 0 ]] && pass
fi

# ---------------------------------------------------------------------------
# 19. Prose carries no em-dash. It is a recognizable machine-writing tell, and
#     the sweep that removed ~1600 of them is worthless without a gate: one
#     authoring slip and the convention rots back file by file. Three classes
#     are wire format rather than prose, exempted by line pattern rather than by
#     file so a real slip on the same line still fails: the CHANGELOG section
#     heading (CHANGELOG.md itself is a historical record, never rewritten), and
#     the two managed-block markers already written into every user's
#     CLAUDE.md/GEMINI.md/AGENTS.md, where changing the string would orphan the
#     existing block instead of replacing it. This file builds the character from
#     bytes on purpose, so it can scan itself without matching its own source.
# ---------------------------------------------------------------------------
check "prose carries no em-dash"
_emdash="$(printf '\xe2\x80\x94')"
_em="$(grep -rn "$_emdash" \
    "$REPO_DIR"/rules "$REPO_DIR"/skills "$REPO_DIR"/commands "$REPO_DIR"/agents \
    "$REPO_DIR"/adapters "$REPO_DIR"/hooks "$REPO_DIR"/docs \
    "$REPO_DIR"/README.md "$REPO_DIR"/CLAUDE.md "$REPO_DIR"/CONTRIBUTING.md \
    "$REPO_DIR"/LICENSE "$REPO_DIR"/check.sh "$REPO_DIR"/sync.sh "$REPO_DIR"/install.sh \
    "$REPO_DIR"/.github/workflows/release.yml 2>/dev/null \
    | grep -v 'CHANGELOG' \
    | grep -v 'CRAFTKIT-INJECTED-RULES' || true)"
if [[ -n "$_em" ]]; then
    fail "em-dash in prose, so use a comma, colon, semicolon, period, or parentheses:"
    echo "$_em" | sed 's/^/      /'
else
    pass
fi

# ---------------------------------------------------------------------------
# 20. In-page anchor links resolve. GitHub derives a heading's anchor from its
#     text, so editing heading wording silently retargets every link to it.
#     The em-dash sweep in v1.29.0 rewrote three README headings and broke four
#     TOC links that way: " - " collapses to "--" in a slug but ", " collapses
#     to "-", so the link kept a dash the heading no longer had. Nothing failed
#     loudly, because a dead in-page anchor just scrolls nowhere.
# ---------------------------------------------------------------------------
check "in-page anchor links resolve"
_anchor_out="$(python3 - "$REPO_DIR" <<'PY' 2>/dev/null
import io, os, re, sys, glob
root = sys.argv[1]
def slug(h):
    s = h.strip().lower()
    s = re.sub(r'[^\w\s-]', '', s)
    return s.replace(' ', '-')
files = ["README.md", "CLAUDE.md", "CONTRIBUTING.md", "CHANGELOG.md"]
for pat in ("rules/*.md", "skills/*/SKILL.md", "commands/*.md", "agents/*.md"):
    files += [os.path.relpath(p, root) for p in glob.glob(os.path.join(root, pat))]
files += [os.path.relpath(p, root) for p in glob.glob(os.path.join(root, "docs/**/*.md"), recursive=True)]
for f in files:
    full = os.path.join(root, f)
    if not os.path.exists(full):
        continue
    txt = io.open(full, encoding="utf-8").read()
    heads = {slug(m.group(1)) for m in re.finditer(r'^#{1,6}\s+(.*)$', txt, re.M)}
    for m in re.finditer(r'\]\(#([^)]+)\)', txt):
        if m.group(1) not in heads:
            print("%s -> #%s" % (f, m.group(1)))
PY
)"
if [[ -n "$_anchor_out" ]]; then
    fail "in-page anchor does not match any heading, so the link scrolls nowhere:"
    echo "$_anchor_out" | sed 's/^/      /'
else
    pass
fi

# ---------------------------------------------------------------------------
# 21. The managed block survives a third-party tool eating its BEGIN marker.
#     Behavioral. graphify installs a `## graphify` section into the same
#     CLAUDE.md and its uninstall strips from that heading to the next `## `
#     heading, which lands inside our block, taking the BEGIN comment with it.
#     Before the guard, the BEGIN-present test in _rebuild_claude_md then took
#     the append branch and wrote a SECOND block, leaving the orphaned copy
#     loading as always-on rules with nothing to signal it. Verified against a
#     fixture rather than argued, because the failure is silent by construction.
# ---------------------------------------------------------------------------
check "managed block recovers from an orphaned END marker"
_rb=0
_fx="$(mktemp -d)"
mkdir -p "$_fx/rules"
printf -- '---\nname: probe-rule\n---\n\n## Probe section\n- probe constraint\n' > "$_fx/rules/probe.md"
# CLAUDE.md as graphify's uninstall leaves it: user prose, stale rule text, orphaned END.
{
    printf '# CLAUDE.md\n\n## my own notes\nkeep me\n\n'
    printf '## Layer constraints\n- stale rule text\n'
    printf '<!-- END CRAFTKIT -->\n'
} > "$_fx/CLAUDE.md"
(
    set +u
    # shellcheck disable=SC1090
    . "$REPO_DIR/adapters/claude.sh" >/dev/null 2>&1
    # Assigned after sourcing on purpose: claude.sh sets both unconditionally.
    CLAUDE_MD="$_fx/CLAUDE.md"
    CLAUDE_RULES_DIR="$_fx/rules"
    _rebuild_claude_md
) >/dev/null 2>&1
_begins="$(grep -cF '<!-- BEGIN CRAFTKIT (' "$_fx/CLAUDE.md" 2>/dev/null || echo 0)"
_ends="$(grep -cF '<!-- END CRAFTKIT -->' "$_fx/CLAUDE.md" 2>/dev/null || echo 0)"
[[ "$_begins" -eq 1 ]] || { fail "expected exactly 1 BEGIN marker after recovery, got $_begins"; _rb=1; }
[[ "$_ends" -eq 1 ]] || { fail "orphaned END marker survived, so the block is duplicated ($_ends END markers)"; _rb=1; }
grep -qF 'keep me' "$_fx/CLAUDE.md" \
    || { fail "recovery destroyed the user's own content outside the block"; _rb=1; }
grep -qF 'probe constraint' "$_fx/CLAUDE.md" \
    || { fail "fresh rule body missing after recovery"; _rb=1; }
rm -rf "$_fx"
[[ $_rb -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 22. No adapter still carries the retired AGENTIC-SKILLS marker. The rename to
#     CRAFTKIT was applied per adapter, and a partial application is worse than
#     none: the migration in sync.sh renames the block already on disk, so an
#     adapter left pointing at the old literal cannot find its marker, takes the
#     append branch, and writes a SECOND block. That happened during this very
#     change (two of three adapters silently no-op'd), producing duplicate blocks
#     in CLAUDE.md and AGENTS.md. Cheap grep, so the half-done state cannot ship.
# ---------------------------------------------------------------------------
check "no adapter carries the retired managed-block marker"
_legacy="$(grep -rn 'AGENTIC-SKILLS' "$REPO_DIR"/adapters 2>/dev/null || true)"
if [[ -n "$_legacy" ]]; then
    fail "adapter still references the retired AGENTIC-SKILLS marker, so it will append a duplicate block:"
    echo "$_legacy" | sed 's/^/      /'
else
    pass
fi

# ---------------------------------------------------------------------------
# 23. The enforcement gates actually refuse. The routing hook only injects text,
#     and an agent can read text and hand-roll the work anyway, which is the
#     failure this trio exists to stop: an edit with no skill invoked, a turn
#     that reports done having skipped the verification command, and a turn that
#     announced a skill and then hand-rolled the work. Behavioral, because a gate
#     that silently returns {} is indistinguishable from no gate, and all three
#     fail OPEN by design, so a broken one looks fine in use.
# ---------------------------------------------------------------------------
check "enforcement gates refuse and fail open"
if ! command -v node >/dev/null 2>&1; then
    echo "    skipped (node not on PATH)"
else
    _gx="$(mktemp -d)"
    mkdir -p "$_gx/proj" && echo '{}' > "$_gx/proj/package.json"
    python3 - "$_gx" << 'PYEOF'
import json, sys
gx = sys.argv[1]


def assistant(items):
    return {"type": "assistant", "message": {"role": "assistant", "content": items}}


def use(name, inp):
    return {"type": "tool_use", "name": name, "input": inp}


# The other role-user impostor, and the one a tool_result fixture does not cover: an
# injected entry carries text, so only isMeta separates it from a real prompt. A Skill body
# (isMeta + turnCompanion + sourceToolUseID) and stop-hook feedback (isMeta + session_id)
# both land mid-turn, and reading either as a turn start truncates the turn.
def injected(text, **extra):
    entry = {"type": "user", "isMeta": True,
             "message": {"role": "user", "content": [{"type": "text", "text": text}]}}
    entry.update(extra)
    return entry


BODY = "**Model:** everyday. ...skill instructions..."


def build(mode):
    lines = [{"type": "user", "message": {"role": "user", "content": "edit foo"}}]
    if mode == "prior-routed":
        # An EARLIER turn routed; this turn is the continuation that edits.
        lines.append(assistant([use("Skill", {"skill": "fe-test"})]))
        lines.append({"type": "user", "message": {"role": "user", "content": "apply the fixes"}})
    if mode == "notification":
        lines = [{"type": "user", "message": {"role": "user",
                  "content": "<task-notification>\n<task-id>abc</task-id>\n"}}]
    if mode in ("skill", "skill-injected"):
        lines.append(assistant([use("Skill", {"skill": "fe-test"})]))
    if mode in ("skill-injected", "injected-only"):
        lines.append(injected(BODY, turnCompanion=True, sourceToolUseID="tu_1"))
    lines.append(assistant([use("Edit", {"file_path": "/x/ViewFoo.tsx"})]))
    # A tool_result also has role user, and must not be read as a new turn.
    lines.append({"type": "user", "message": {"role": "user",
                  "content": [{"type": "tool_result", "content": "ok"}]}})
    if mode == "verified":
        lines.append(assistant([use("Bash", {"command": "rtk tsc --noEmit && rtk lint ViewFoo.tsx"})]))
    return lines


for mode in ("bare", "skill", "verified", "skill-injected", "injected-only",
             "prior-routed", "notification"):
    with open("%s/%s.jsonl" % (gx, mode), "w") as f:
        f.write("\n".join(json.dumps(x) for x in build(mode)) + "\n")

# Announce-gate fixtures. The skill name is fixture-local (resolved from the cwd's own
# .claude/) so the case does not depend on what this machine happens to have installed.
def announced(text, invoke=None):
    lines = [{"type": "user", "message": {"role": "user", "content": "write the PR message"}}]
    if invoke:
        lines.append(assistant([use("Skill", {"skill": invoke})]))
    lines.append(assistant([{"type": "text", "text": text}]))
    return lines


REAL = "zzz-fixture-skill"
announce_cases = {
    "announce-lied": announced("Running /%s [cheapest]: generate it.\nHere is the message." % REAL),
    "announce-kept": announced("Running /%s [cheapest]: generate it." % REAL, invoke=REAL),
    "announce-inline": announced("No skill matched for this request. Responding directly.\nThe format is `Running /%s [cheapest]` with no block under it." % REAL),
    "announce-fenced": announced("No skill matched for this request. Responding directly.\nExample:\n```\nRunning /%s [cheapest]: reason.\n```\nThat is documentation." % REAL),
    "announce-unknown": announced("Running /zzz-not-installed [cheapest]: generate it."),
    # Check 2: the turn claimed nothing at all, which is how check 1 gets defeated.
    "declare-silent": announced("Here is the PR message you asked for."),
    "declare-nomatch": announced("No skill matched for this request. Responding directly.\nHere it is."),
    "declare-bold": announced("**No skill matched for this request.** Responding directly."),
    "declare-empty": announced(""),
    "declare-by-invoking": announced("Here it is, no announcement line.", invoke=REAL),
}

# The real order of a skill-driven turn: announce, invoke, skill body arrives, agent keeps
# working. The body is where the turn used to restart, discarding both the announcement and
# the Skill call, so an honest turn could not end.
announce_cases["announce-across-injection"] = [
    {"type": "user", "message": {"role": "user", "content": "write the PR message"}},
    assistant([{"type": "text", "text": "Running /%s [cheapest]: generate it." % REAL}]),
    assistant([use("Skill", {"skill": REAL})]),
    injected(BODY, turnCompanion=True, sourceToolUseID="tu_1"),
    assistant([{"type": "text", "text": "Here is the message."}]),
]
# Stop feedback is the other injected class, and it erased the declaration the retry had
# just added, so the block repeated instead of clearing.
announce_cases["declare-across-stop-feedback"] = [
    {"type": "user", "message": {"role": "user", "content": "write the PR message"}},
    assistant([{"type": "text", "text": "No skill matched for this request. Responding directly."}]),
    injected("Stop hook feedback: No routing declaration this turn.", session_id="s"),
    assistant([{"type": "text", "text": "Here is the message."}]),
]
# Negative control: widening the turn must not make an undeclared turn look declared.
announce_cases["declare-silent-across-injection"] = [
    {"type": "user", "message": {"role": "user", "content": "write the PR message"}},
    injected(BODY, turnCompanion=True, sourceToolUseID="tu_1"),
    assistant([{"type": "text", "text": "Here is the PR message you asked for."}]),
]

# One file edited four times is one file: the reason line counted tool calls, not files,
# and reported "21 file(s)" for six. Found when this gate fired on its own author's turn.
repeat = [{"type": "user", "message": {"role": "user", "content": "edit foo"}}]
for _ in range(4):
    repeat.append(assistant([use("Edit", {"file_path": "/x/ViewFoo.tsx"})]))
with open("%s/repeat-edits.jsonl" % gx, "w") as f:
    f.write("\n".join(json.dumps(x) for x in repeat) + "\n")

for name, lines in announce_cases.items():
    with open("%s/%s.jsonl" % (gx, name), "w") as f:
        f.write("\n".join(json.dumps(x) for x in lines) + "\n")

# A subagent's transcript is its own file and every entry carries isSidechain.
side = build("bare")
for entry in side:
    entry["isSidechain"] = True
with open("%s/sidechain.jsonl" % gx, "w") as f:
    f.write("\n".join(json.dumps(x) for x in side) + "\n")
PYEOF
    # TMPDIR is redirected into the fixture so the gate's one-ask-per-turn stamps land
    # there and vanish with it, instead of leaking between check runs.
    _skillgate() {
        printf '{"session_id":"%s","transcript_path":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3" \
            | TMPDIR="$_gx" node "$REPO_DIR/hooks/gate-skill-first.js" 2>/dev/null
    }
    _stopgate() {
        printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"%s}' "${3:-v$RANDOM}" "$1" "$_gx/proj" "${2:-}" \
            | TMPDIR="$_gx" node "$REPO_DIR/hooks/gate-verify-on-stop.js" 2>/dev/null
    }
    _gd=0
    _skillgate s1 "$_gx/bare.jsonl" /x/ViewFoo.tsx | grep -q '"permissionDecision":"ask"' \
        || { fail "skill gate let an unrouted source edit through, so the routing gate is advisory again"; _gd=1; }
    _skillgate s2 "$_gx/skill.jsonl" /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate still asks after a Skill call, so every routed edit costs a prompt"; _gd=1; }
    _skillgate s3 "$_gx/bare.jsonl" /x/notes.md | grep -q 'permissionDecision' \
        && { fail "skill gate asks on a non-source file, which gates prose edits for no reason"; _gd=1; }
    _skillgate s4 /nope/missing.jsonl /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate blocks on an unreadable transcript instead of failing open"; _gd=1; }
    # One interruption per unrouted turn. Per edit, a ten-edit turn costs ten prompts,
    # which trains the human to click through the gate, which is the gate not existing.
    _skillgate s5 "$_gx/bare.jsonl" /x/ViewFoo.tsx >/dev/null
    _skillgate s5 "$_gx/bare.jsonl" /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate asks twice in one turn, so a multi-edit turn is a wall of prompts"; _gd=1; }
    _skillgate s6 "$_gx/bare.jsonl" /x/ViewFoo.tsx | grep -q '"permissionDecision":"ask"' \
        || { fail "skill gate stamp leaks across sessions, so a new session inherits an ask it never made"; _gd=1; }
    # A subagent has its own transcript, so the parent's Skill call is not in it. Gating it
    # would prompt on every edit a /parallel-build implementer makes, at a point where a
    # background agent may have nobody able to answer.
    _skillgate s7 "$_gx/sidechain.jsonl" /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate asks inside a subagent, so every parallel-build implementer stalls on a prompt"; _gd=1; }
    # The skill body lands between the Skill call and the edits the skill prescribes, which
    # is where every routed turn does its work. Truncating there gated the routed case.
    _skillgate s8 "$_gx/skill-injected.jsonl" /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate asks after a Skill call once the skill body arrives, so every routed edit costs a prompt"; _gd=1; }
    # Negative control: the same injected entry with no Skill call anywhere must still ask,
    # or widening the turn has disarmed the gate rather than fixed it.
    _skillgate s9 "$_gx/injected-only.jsonl" /x/ViewFoo.tsx | grep -q '"permissionDecision":"ask"' \
        || { fail "skill gate stopped asking on an unrouted turn containing an injected entry, so the turn fix disarmed the gate"; _gd=1; }
    # Session scope, not turn scope. Asking on every unrouted source edit fires at 62% of
    # source-editing turns (measured); asking only when the session never routed fires at
    # 18% and still catches the misses. The turns in between are continuations whose
    # routing happened earlier, and re-asking there is what trains click-through.
    _skillgate s10 "$_gx/prior-routed.jsonl" /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate asks on a continuation whose session already routed, the 62%-firing behavior the session scope replaces"; _gd=1; }
    _skillgate s11 "$_gx/notification.jsonl" /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate asks on a background-task notification, which is not a prompt and carries no routing intent"; _gd=1; }
    # A system-reminder can prefix a genuine prompt in the same entry, so treating it as a
    # notification would disarm the gate on ordinary routable work. Found in review after
    # the regex had been widened to match it with no spec line behind it.
    python3 - "$_gx" << 'PYEOF'
import json, sys
gx = sys.argv[1]
lines = [{"type": "user", "message": {"role": "user", "content":
          "<system-reminder>context</system-reminder>\nadd a field to the booking form"}},
         {"type": "assistant", "message": {"role": "assistant", "content": [
             {"type": "tool_use", "name": "Edit", "input": {"file_path": "/x/ViewFoo.tsx"}}]}}]
with open("%s/reminder-prefixed.jsonl" % gx, "w") as f:
    f.write("\n".join(json.dumps(x) for x in lines) + "\n")
# A session past TAIL_BYTES must not lose its routing history: the transcript only grows,
# so reading a short window as "never routed" switched the gate off for the rest of any
# long session. Padded past 1MB with an early Skill call that only a full scan can see.
pad = {"type": "assistant", "message": {"role": "assistant", "content": [
    {"type": "text", "text": "x" * 2000}]}}
big = [{"type": "user", "message": {"role": "user", "content": "build the thing"}},
       {"type": "assistant", "message": {"role": "assistant", "content": [
           {"type": "tool_use", "name": "Skill", "input": {"skill": "fe-test"}}]}}]
big += [pad] * 600
big += [{"type": "user", "message": {"role": "user", "content": "apply the fixes"}},
        {"type": "assistant", "message": {"role": "assistant", "content": [
            {"type": "tool_use", "name": "Edit", "input": {"file_path": "/x/ViewFoo.tsx"}}]}}]
with open("%s/truncated-routed.jsonl" % gx, "w") as f:
    f.write("\n".join(json.dumps(x) for x in big) + "\n")
PYEOF
    _skillgate s12 "$_gx/reminder-prefixed.jsonl" /x/ViewFoo.tsx | grep -q '"permissionDecision":"ask"' \
        || { fail "skill gate treats a system-reminder-prefixed real prompt as a notification, silently disarming on routable work"; _gd=1; }
    _skillgate s13 "$_gx/truncated-routed.jsonl" /x/ViewFoo.tsx | grep -q 'permissionDecision' \
        && { fail "skill gate loses a session's routing history once the transcript passes the tail window, disabling itself for the rest of a long session"; _gd=1; }
    # The whole-file Skill count is cached by byte offset so a long session stops paying a
    # full rescan on every Read and Edit. A cache is only safe if it agrees with a rescan:
    # appended calls add on, a half-written line is counted once it completes and never
    # twice, and a file that shrank was replaced, so its stale count must not survive.
    mkdir -p "$_gx/cc-tmp"
    TMPDIR="$_gx/cc-tmp" node -e '
const fs = require("fs");
const src = fs.readFileSync(process.argv[1], "utf8") + "\nmodule.exports.__count = countSkillCalls;";
fs.writeFileSync(process.argv[2] + "/t.js", src);
const count = require(process.argv[2] + "/t.js").__count;
const f = process.argv[2] + "/cc.jsonl";
const call = JSON.stringify({ type: "tool_use", name: "Skill" });
fs.writeFileSync(f, call + "\n");
const got = [count(f)];
fs.appendFileSync(f, call + "\n" + call.slice(0, 10)); got.push(count(f));
fs.appendFileSync(f, call.slice(10) + "\n"); got.push(count(f));
fs.writeFileSync(f, "{}\n"); got.push(count(f));
process.exit(got.join() === "1,2,3,0" ? 0 : (console.log(got.join()), 1));
' "$REPO_DIR/hooks/craftkit-transcript.js" "$_gx/cc-tmp" >/dev/null \
        || { fail "cached Skill count disagrees with a full rescan (appended, split-line, or replaced transcript), so the gate misreads a long session's routing history"; _gd=1; }
    _stopgate "$_gx/bare.jsonl" | grep -q '"decision":"block"' \
        || { fail "stop gate let a turn end with edits and no verification command"; _gd=1; }
    _stopgate "$_gx/verified.jsonl" | grep -q '"decision"' \
        && { fail "stop gate blocks after the gates ran, which makes ending any turn impossible"; _gd=1; }
    # A retry is judged, not waved through, and the blocks are counted so the loop still
    # terminates. Honoring stop_hook_active unconditionally meant only the first stop
    # attempt was ever evaluated, which is a bypass requiring nothing but a second attempt.
    _stopgate "$_gx/bare.jsonl" "" t13a >/dev/null
    _stopgate "$_gx/bare.jsonl" ',"stop_hook_active":true' t13a | grep -q '"decision":"block"' \
        || { fail "stop gate waves through a retry that changed nothing, so being blocked once is the whole cost of skipping verification"; _gd=1; }
    _stopgate "$_gx/bare.jsonl" ',"stop_hook_active":true' t13a | grep -q '"decision"' \
        && { fail "stop gate blocks a third attempt, so a turn it cannot satisfy can never end"; _gd=1; }
    _stopgate "$_gx/verified.jsonl" ',"stop_hook_active":true' t13b | grep -q '"decision"' \
        && { fail "stop gate blocks a retry that fixed the problem, so correcting the turn does not clear it"; _gd=1; }
    # Editing through the shell leaves no Edit tool call, so the turn's file list cannot
    # come from tool calls alone. Caught during this change: both gates were blind to it,
    # which is the route an agent bypassing a skill is most likely to take.
    if command -v git >/dev/null 2>&1; then
        (cd "$_gx/proj" && git init -q . && git add -A && git commit -qm init >/dev/null 2>&1) || true
        echo x > "$_gx/proj/ViewX.tsx"
        python3 - "$_gx" << 'PYEOF'
import json, sys
gx = sys.argv[1]


def turn(prompt, command):
    return [{"type": "user", "message": {"role": "user", "content": prompt}},
            {"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "name": "Bash", "input": {"command": command}}]}}]


cases = {"shell": turn("edit", "sed -i '' s/a/b/ ViewX.tsx"),
         "scratch": [{"type": "user", "message": {"role": "user", "content": "draft it"}},
                     {"type": "assistant", "message": {"role": "assistant", "content": [
                         {"type": "tool_use", "name": "Write",
                          "input": {"file_path": "/private/tmp/claude-1/x/scratchpad/probe.ts"}}]}}],
         "readonly": turn("what is this", "cat ViewX.tsx"),
         "delegated": [{"type": "user", "message": {"role": "user", "content": "build it"}},
                       {"type": "assistant", "message": {"role": "assistant", "content": [
                           {"type": "tool_use", "name": "Agent", "input": {"prompt": "implement"}}]}}]}
for name, lines in cases.items():
    with open("%s/%s.jsonl" % (gx, name), "w") as f:
        f.write("\n".join(json.dumps(x) for x in lines) + "\n")
PYEOF
        _stopgate "$_gx/shell.jsonl" | grep -q '"decision":"block"' \
            || { fail "stop gate misses a shell-route edit (sed -i), the bypass most likely to skip a skill"; _gd=1; }
        _stopgate "$_gx/readonly.jsonl" | grep -q '"decision"' \
            && { fail "stop gate blocks a read-only turn on a dirty tree, so pre-existing dirt gates every turn"; _gd=1; }
        # A throwaway file cannot be the reason a turn owes a verification run. This gate
        # fired on a PR body drafted in the session scratchpad until it excluded them.
        _stopgate "$_gx/scratch.jsonl" | grep -q '"decision"' \
            && { fail "stop gate demands verification for a scratchpad-only turn, firing on throwaway files"; _gd=1; }
        # Delegating the edits hides them the same way the shell does: a subagent's writes
        # land in ITS transcript, so the parent's turn shows no edits at all.
        _stopgate "$_gx/delegated.jsonl" | grep -q '"decision":"block"' \
            || { fail "stop gate misses edits made by a spawned agent, so delegating skips verification"; _gd=1; }
    fi
    mkdir -p "$_gx/proj/.claude/skills/zzz-fixture-skill"
    _announcegate() {
        printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"%s}' "${3:-a$RANDOM}" "$1" "$_gx/proj" "${2:-}" \
            | TMPDIR="$_gx" node "$REPO_DIR/hooks/gate-announce-honored.js" 2>/dev/null
    }
    # The lie the other two gates cannot see: prose-only turn, zero edits, so neither the
    # PreToolUse matcher nor the verify gate ever arms.
    _announcegate "$_gx/announce-lied.jsonl" | grep -q '"decision":"block"' \
        || { fail "announce gate let a turn end having announced a skill it never invoked"; _gd=1; }
    _announcegate "$_gx/announce-kept.jsonl" | grep -q '"decision"' \
        && { fail "announce gate blocks after the skill actually ran, so honest turns cannot end"; _gd=1; }
    # Meta-discussion about the gate must not trip the gate, or documenting it is impossible.
    _announcegate "$_gx/announce-inline.jsonl" | grep -q '"decision"' \
        && { fail "announce gate trips on a backticked mid-sentence mention, so prose about it blocks"; _gd=1; }
    _announcegate "$_gx/announce-fenced.jsonl" | grep -q '"decision"' \
        && { fail "announce gate trips on a fenced example, which blocks every doc that shows the format"; _gd=1; }
    # A name resolving to nothing installed is prose or a typo, and a gate that guesses is
    # worse than one that abstains.
    _announcegate "$_gx/announce-unknown.jsonl" | grep -q '"decision"' \
        && { fail "announce gate blocks on a skill that is not installed, so any /word in prose blocks"; _gd=1; }
    _announcegate "$_gx/announce-lied.jsonl" "" t13c >/dev/null
    _announcegate "$_gx/announce-lied.jsonl" ',"stop_hook_active":true' t13c | grep -q '"decision":"block"' \
        || { fail "announce gate waves through a retry that still has not invoked what it announced"; _gd=1; }
    _announcegate "$_gx/announce-lied.jsonl" ',"stop_hook_active":true' t13c | grep -q '"decision"' \
        && { fail "announce gate blocks a third attempt, so a turn it cannot satisfy can never end"; _gd=1; }
    _announcegate "$_gx/announce-kept.jsonl" ',"stop_hook_active":true' t13d | grep -q '"decision"' \
        && { fail "announce gate blocks a retry that actually invoked the skill, so honest correction does not clear it"; _gd=1; }
    _announcegate /nope/missing.jsonl | grep -q '"decision"' \
        && { fail "announce gate blocks on an unreadable transcript instead of failing open"; _gd=1; }
    # Check 2. Without it, check 1 is defeated by dropping the announcement, which trades
    # the lie for a silent skip and loses the tell entirely.
    _announcegate "$_gx/declare-silent.jsonl" | grep -q '"decision":"block"' \
        || { fail "announce gate lets a turn end with no routing declaration, so silently skipping the line beats the gate"; _gd=1; }
    _announcegate "$_gx/declare-nomatch.jsonl" | grep -q '"decision"' \
        && { fail "announce gate blocks a declared no-match, which is the sanctioned way to route nothing"; _gd=1; }
    _announcegate "$_gx/declare-bold.jsonl" | grep -q '"decision"' \
        && { fail "announce gate blocks a bolded no-match line, so formatting the declaration breaks it"; _gd=1; }
    # A Skill call IS the declaration; requiring prose on top would block every honest turn
    # that just invoked the thing.
    _announcegate "$_gx/declare-by-invoking.jsonl" | grep -q '"decision"' \
        && { fail "announce gate demands prose from a turn that invoked a skill, so invoking is not enough"; _gd=1; }
    _announcegate "$_gx/declare-empty.jsonl" | grep -q '"decision"' \
        && { fail "announce gate blocks an empty reply, which is an interrupted turn, not an unrouted one"; _gd=1; }
    # Every skill-driven turn has a body injected mid-turn, so this is the common case, not
    # an edge one: the gate blocked turns that had both announced and invoked.
    _announcegate "$_gx/announce-across-injection.jsonl" | grep -q '"decision"' \
        && { fail "announce gate blocks a turn that announced and invoked, because the skill body reset the turn"; _gd=1; }
    _announcegate "$_gx/declare-across-stop-feedback.jsonl" | grep -q '"decision"' \
        && { fail "announce gate loses a declaration to its own stop feedback, so the block repeats instead of clearing"; _gd=1; }
    # Negative control for check 2, mirroring s9.
    _announcegate "$_gx/declare-silent-across-injection.jsonl" | grep -q '"decision":"block"' \
        || { fail "announce gate stopped seeing an undeclared turn once an injected entry appeared, so the turn fix disarmed check 2"; _gd=1; }

    _stopgate "$_gx/repeat-edits.jsonl" | grep -q 'edited 1 file' \
        || { fail "stop gate counts repeat edits to one file as several files, inflating the reason line"; _gd=1; }
    # A blocked party cannot find the escape hatch in a file comment nobody reads mid-turn.
    _stopgate "$_gx/bare.jsonl" | grep -q 'CRAFTKIT_GATE=off' \
        || { fail "stop gate refusal never names its own escape hatch, unlike the skill gate"; _gd=1; }

    for _g in gate-skill-first.js gate-verify-on-stop.js gate-announce-honored.js; do
        echo 'not json' | node "$REPO_DIR/hooks/$_g" >/dev/null 2>&1 \
            || { fail "$_g exits non-zero on malformed stdin, which surfaces as a tool error every call"; _gd=1; }
    done
    rm -rf "$_gx"
    [[ $_gd -eq 0 ]] && pass
fi

# ---------------------------------------------------------------------------
# 23b. Platform-scoped rules load ONLY where they apply. A rule declaring
#      `platform:` must be absent from the always-on managed block and present in
#      the staging dir the SessionStart hook reads, because the block loads in
#      every project: fe-rules taught EVPMR laws during Kotlin work for exactly
#      as long as nothing checked this. Behavioral on both halves, since the
#      shell half failing open puts the rule back in every session silently, and
#      the hook half failing open loads it on Android.
# ---------------------------------------------------------------------------
check "platform-scoped rules load only on their platform"
if ! command -v node >/dev/null 2>&1; then
    echo "    skipped (node not on PATH)"
else
    _px=0
    _pf="$(mktemp -d)"
    # A rule is platform-scoped exactly when the adapter's own parser says so, so the
    # check uses that function rather than re-deriving the frontmatter read.
    ( . "$REPO_DIR/adapters/claude.sh" >/dev/null 2>&1
      for _r in "$REPO_DIR"/rules/*.md; do
          if _claude_rule_platform "$_r" >/dev/null; then echo "scoped $(basename "$_r" .md)"; fi
      done ) > "$_pf/scoped"
    if [[ ! -s "$_pf/scoped" ]]; then
        fail "no rule declares platform:, so the scoping mechanism ships with nothing using it and rots untested"
        _px=1
    fi
    # Build the block + staging in a sandbox from the adapter's OWN installer, so the
    # assertion depends on this diff, not on whatever a prior sync left in $HOME. Reading
    # real ~/.craftkit and ~/.claude made the gate fail on a machine that never ran sync.
    # Staged where the hook actually looks: os.homedir()/.craftkit/claude-rules. Staging
    # elsewhere and then running the hook with the real HOME meant the hook read whatever a
    # prior sync had left there, so this check passed only on a machine that had synced and
    # could never pass on a fresh checkout. CI found it on the first run.
    mkdir -p "$_pf/home/.craftkit/claude-rules" "$_pf/cmds"
    ( . "$REPO_DIR/adapters/claude.sh" >/dev/null 2>&1
      CLAUDE_RULES_DIR="$_pf/home/.craftkit/claude-rules"; CLAUDE_MD="$_pf/CLAUDE.md"; CLAUDE_COMMANDS_DIR="$_pf/cmds"
      for _r in "$REPO_DIR"/rules/*.md; do
          install_claude_rule "$(basename "$_r" .md)" "$_r" >/dev/null 2>&1
      done )
    while read -r _tag _rn; do
        [[ "$_tag" == "scoped" ]] || continue
        # The staged copy is what the hook reads; the block is what every project loads.
        if ! grep -q "^name: $_rn\$" "$_pf/home/.craftkit/claude-rules/${_rn}.md" 2>/dev/null; then
            fail "rules/$_rn.md is platform-scoped but not staged, so the SessionStart hook has nothing to load"
            _px=1
        fi
        if grep -q "^name: $_rn\$" "$_pf/CLAUDE.md" 2>/dev/null; then
            fail "rules/$_rn.md is platform-scoped yet still in the always-on block, so it loads on every platform"
            _px=1
        fi
    done < "$_pf/scoped"
    # Positive control: an unscoped rule MUST be in the block, else the absence check above
    # passes vacuously against an empty or unbuilt block.
    if ! grep -q "^name: karpathy-guidelines\$" "$_pf/CLAUDE.md" 2>/dev/null; then
        fail "sandbox managed block lacks an always-on rule, so the scoped-absence check proves nothing"
        _px=1
    fi

    _phook() { printf '{"cwd":"%s"}' "$1" | HOME="$_pf/home" node "$REPO_DIR/hooks/craftkit-platform-rules.js" 2>/dev/null; }
    mkdir -p "$_pf/fe" "$_pf/android" "$_pf/bare"
    echo '{}' > "$_pf/fe/package.json"
    : > "$_pf/android/settings.gradle"
    _phook "$_pf/fe" | grep -q 'additionalContext' \
        || { fail "platform-rules hook injects nothing on a package.json project, so fe-rules never loads at all"; _px=1; }
    _phook "$_pf/android" | grep -q 'additionalContext' \
        && { fail "platform-rules hook injects fe rules on a Gradle project, which is the bug the scoping exists to fix"; _px=1; }
    _phook "$_pf/bare" | grep -q 'additionalContext' \
        && { fail "platform-rules hook injects on a directory with no platform marker"; _px=1; }
    echo 'not json' | node "$REPO_DIR/hooks/craftkit-platform-rules.js" >/dev/null 2>&1 \
        || { fail "platform-rules hook exits non-zero on malformed stdin, which surfaces as an error every session"; _px=1; }

    # Cursor is the one tool with native path scoping, so its render must USE it: an
    # alwaysApply:true fe-rules there is the same always-on bug in a different file.
    # Every scoped rule, not just fe-rules: a new platform's rule with no glob row in
    # cursor.sh falls back to alwaysApply and is always-on there, silently.
    while read -r _tag _rn; do
        [[ "$_tag" == "scoped" ]] || continue
        ( . "$REPO_DIR/adapters/cursor.sh" >/dev/null 2>&1
          _cursor_render_rule "$REPO_DIR/rules/${_rn}.md" "$_pf/${_rn}.mdc" ) 2>/dev/null
        grep -q '^globs: ' "$_pf/${_rn}.mdc" 2>/dev/null \
            || { fail "cursor renders scoped rule $_rn without globs (no glob row in cursor.sh), so it stays always-on there"; _px=1; }
        grep -q '^alwaysApply: false$' "$_pf/${_rn}.mdc" 2>/dev/null \
            || { fail "cursor renders scoped rule $_rn as alwaysApply, so its globs never take effect"; _px=1; }
    done < "$_pf/scoped"
    ( . "$REPO_DIR/adapters/cursor.sh" >/dev/null 2>&1
      _cursor_render_rule "$REPO_DIR/rules/karpathy-guidelines.md" "$_pf/k.mdc" ) 2>/dev/null
    grep -q '^alwaysApply: true$' "$_pf/k.mdc" 2>/dev/null \
        || { fail "cursor stopped rendering an unscoped rule as alwaysApply, so the always-on rules went conditional"; _px=1; }

    rm -rf "$_pf"
    [[ $_px -eq 0 ]] && pass
fi

# ---------------------------------------------------------------------------
# 24. The hook table and hooks/ agree in both directions, same invariant as
#     check 13 holds for adapters. A script in hooks/ that no table entry names
#     is never installed, and a table entry with no script installs nothing while
#     registering a command that fails on every event it fires for.
# ---------------------------------------------------------------------------
check "hook table matches hooks/"
_ht=0
_table="$(bash -c ". '$REPO_DIR/adapters/claude.sh' >/dev/null 2>&1; printf '%s\n' \"\${_CRAFTKIT_HOOKS[@]}\"" | cut -d'%' -f1 | sort)"
for _f in "$REPO_DIR"/hooks/*.js; do
    _b="$(basename "$_f")"
    echo "$_table" | grep -qx "$_b" || { fail "hooks/$_b is in no _CRAFTKIT_HOOKS entry, so sync never installs it"; _ht=1; }
done
for _b in $_table; do
    [[ -f "$REPO_DIR/hooks/$_b" ]] || { fail "_CRAFTKIT_HOOKS names $_b, but hooks/$_b does not exist"; _ht=1; }
    grep -q "$_b" "$README" || { fail "$_b is installed but undocumented in README"; _ht=1; }
done
[[ $_ht -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 25. sync.sh refuses a downgrade. The state files record names only, so a sync
#     from a checkout older than the install uninstalls every rule added since,
#     silently: a one-commit-stale main removed flag-safety from all four tools
#     that way, and the only symptom was rules quietly reverting. Behavioral,
#     because a grep for the guard cannot tell whether it fires. HOME is
#     redirected into the fixture, which contains every write: each adapter
#     destination is $HOME-derived, and the refusal path exits before any
#     adapter is sourced.
# ---------------------------------------------------------------------------
check "sync refuses a downgrade"
_vg=0
_repo_v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_DIR/package.json" | head -1)"
if [[ -z "$_repo_v" ]]; then
    fail "package.json has no readable version, so the downgrade guard cannot compare"
    _vg=1
else
    _vgx="$(mktemp -d)"
    mkdir -p "$_vgx/.craftkit-state"
    # Only the REFUSAL runs sync.sh end to end, because it exits before sourcing any
    # adapter and costs 0.07s. The proceed paths would each complete a full four-adapter
    # sync into the fixture HOME at ~75s apiece, which turned this gate from seconds into
    # minutes, and a gate nobody waits for is a gate nobody runs. They are covered below
    # by unit-testing the comparison and asserting the wiring.
    echo "99.0.0" > "$_vgx/.craftkit-state/version"
    _out="$(HOME="$_vgx" bash "$REPO_DIR/sync.sh" 2>&1)" && _rc=0 || _rc=$?
    printf '%s' "$_out" | grep -q "Refusing to sync" \
        || { fail "sync.sh proceeds from a checkout older than the install, silently uninstalling newer rules"; _vg=1; }
    printf '%s' "$_out" | grep -q "99.0.0" \
        || { fail "downgrade refusal does not name the installed version, so the gap is not diagnosable"; _vg=1; }
    [[ $_rc -ne 0 ]] \
        || { fail "sync.sh exits 0 when refusing a downgrade, so a wrapper or hook reads it as success"; _vg=1; }
    # The override is asserted by wiring, not behavior: exercising it completes a full
    # four-adapter sync (~75s). The refusal above is the dangerous direction and stays
    # end to end; an override that silently failed would only block a deliberate
    # downgrade, which fails safe.
    grep -q 'CRAFTKIT_ALLOW_DOWNGRADE' "$REPO_DIR/sync.sh" \
        || { fail "sync.sh has no CRAFTKIT_ALLOW_DOWNGRADE override, so a deliberate downgrade is impossible"; _vg=1; }
    # Ordering, tested on the real function rather than through a sync. Extraction fails
    # loudly if the function is renamed, which is the sensor working.
    sed -n '/^_ck_version_lt()/,/^}/p' "$REPO_DIR/sync.sh" > "$_vgx/cmp.sh"
    [[ -s "$_vgx/cmp.sh" ]] \
        || { fail "_ck_version_lt not found in sync.sh, so the downgrade guard has no comparison to test"; _vg=1; }
    for _case in "1.9.0 1.10.0 older" "1.10.0 1.9.0 newer" "1.35.0 1.35.0 newer" \
                 "1.35.0 1.35.1 older" "1.2 1.2.1 older" "2.0.0 1.99.99 newer"; do
        set -- $_case
        _got="$(bash -c ". '$_vgx/cmp.sh'; if _ck_version_lt $1 $2; then echo older; else echo newer; fi")"
        [[ "$_got" == "$3" ]] \
            || { fail "version ordering wrong: $1 vs $2 read as $_got, expected $3"; _vg=1; }
    done
    # Wiring: a guard that never records leaves the next run nothing to compare against.
    grep -q '_ck_version_file"$' "$REPO_DIR/sync.sh" \
        || { fail "sync.sh never writes the synced version, so the guard has no baseline after a first run"; _vg=1; }
    grep -q 'f "$_ck_version_file"' "$REPO_DIR/sync.sh" \
        || { fail "sync.sh does not treat a missing version file as a first run, so a fresh install cannot sync"; _vg=1; }
    rm -rf "$_vgx"
fi
[[ $_vg -eq 0 ]] && pass


# ---------------------------------------------------------------------------
# 26. The rubric exists once. partials/ponytail-rubric.md is injected into the
#     cold reviewer and rules/karpathy-guidelines.md is what the writing side
#     authors under, so the two drifting apart means review scores code by a
#     list the author never saw. Byte-for-byte, because "author under the exact
#     list review uses" is the design and a paraphrase breaks it silently.
#     Also holds the always-on inventory to the actual contents of rules/,
#     which listed 3 of 5 for two releases.
# ---------------------------------------------------------------------------
check "one rubric, and an honest rule inventory"
_rb=0
_rbf="$(mktemp)"
awk '/^\| Tag \| Fails when \|/{f=1} f{print} /^Protected, never counted/{if(f)exit}' \
    "$REPO_DIR/rules/karpathy-guidelines.md" > "$_rbf"
[[ -s "$_rbf" ]] \
    || { fail "no rubric block found in rules/karpathy-guidelines.md, so the writing side has no list to author under"; _rb=1; }
_rbp="$(mktemp)"
awk '/^\| Tag \| Fails when \|/{f=1} f{print} /^Protected, never counted/{if(f)exit}' \
    "$REPO_DIR/partials/ponytail-rubric.md" > "$_rbp"
if ! diff -q "$_rbf" "$_rbp" >/dev/null 2>&1; then
    fail "partials/ponytail-rubric.md has drifted from the rubric in rules/karpathy-guidelines.md, so the reviewer scores by a list the author never saw"
    _rb=1
fi
rm -f "$_rbf" "$_rbp"
# The inventory is prose, so only a check keeps it true.
for _r in "$RULES_DIR"/*.md; do
    _rn="$(basename "$_r" .md)"
    grep -q "^- \`$_rn\`" "$REPO_DIR/rules/using-agent-skills.md" \
        || { fail "rules/$_rn.md is always-on but missing from the inventory in using-agent-skills.md, which then understates what every session loads"; _rb=1; }
done
[[ $_rb -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 27. Two drifts that only surface much later.
#     (a) A pointer to content that moved into partials/. Seven call sites named
#         using-agent-skills for the classifier after v1.33.0 moved it, and
#         team-build's reference resolved in neither file because it splices
#         nothing. A wrong pointer reads as a real instruction and sends the
#         agent to a section that is not there.
#     (b) EVPMR in an always-on rule. fe-rules is platform: fe precisely so
#         EVPMR stays out of Kotlin and Swift sessions; karpathy-guidelines
#         carried the same thresholds always-on and undid it.
# ---------------------------------------------------------------------------
check "no stale partial pointers, no EVPMR in always-on rules"
_sp=0
# (a) The classifier and its Step 5 live in the partial now.
if grep -rn 'classifier from `using-agent-skills`' "$REPO_DIR/commands" "$REPO_DIR/rules" "$REPO_DIR/skills" >/dev/null 2>&1; then
    fail "a file points at using-agent-skills for the parallel classifier, which moved to partials/parallel-classifier.md"
    _sp=1
fi
if grep -rn 'Step 5.*(`using-agent-skills`)' "$REPO_DIR/commands" >/dev/null 2>&1; then
    fail "a command points at using-agent-skills for Step 5, which moved to partials/parallel-classifier.md"
    _sp=1
fi
# (c) The platform-agnostic reviewers run on all three platforms (the classifier says so),
#     so an EVPMR layer recital in them is unusable on .kt and .swift and drifts from
#     fe-rules with nothing holding it.
for _f in "$REPO_DIR/agents/code-quality.md" "$REPO_DIR/skills/code-quality/SKILL.md"; do
    if grep -qE "usePresenter|View\*\.tsx|Presenter\*?\.ts" "$_f"; then
        fail "${_f#$REPO_DIR/} is platform-agnostic yet recites EVPMR layer artifacts, which it cannot apply on a .kt or .swift diff"
        _sp=1
    fi
done
# (b) An always-on rule is one with no platform: frontmatter. EVPMR belongs only in a
#     platform-scoped rule, or the scoping mechanism is decorative.
for _r in "$RULES_DIR"/*.md; do
    _claude_rule_platform_probe() {
        awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^platform:/{found=1;exit} END{exit(found?0:1)}' "$1"
    }
    if ! _claude_rule_platform_probe "$_r"; then
        if grep -qE "Presenter\*?\.ts|View\*\.tsx|usePresenter" "$_r"; then
            fail "$(basename "$_r") is always-on yet prescribes EVPMR layer artifacts, so those laws load on Android and iOS and defeat fe-rules' platform scoping"
            _sp=1
        fi
    fi
done
[[ $_sp -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 28. A hook dropped from _CRAFTKIT_HOOKS is uninstalled, file AND settings.json
#     registration. Without a prune pass, retiring a hook orphaned both: the
#     machine kept firing a gate whose source was deleted, with no signal. Same
#     shape CLAUDE.md documents for adapter retirement, and it bit on the first
#     real hook retirement. Static, because a behavioral run means a full sync
#     into a fixture HOME at ~75s; the prune logic is asserted by wiring plus a
#     state file whose absence would make the pass a no-op.
# ---------------------------------------------------------------------------
check "a retired hook is pruned, not orphaned"
_ph=0
grep -q "_claude_prune_hooks" "$REPO_DIR/adapters/claude.sh" \
    || { fail "adapters/claude.sh has no hook prune pass, so a retired hook stays installed and registered forever"; _ph=1; }
grep -q "_claude_prune_hooks" <(sed -n '/^install_claude_craftkit_hook()/,/^}/p' "$REPO_DIR/adapters/claude.sh") \
    || { fail "the prune pass is never called from install_claude_craftkit_hook, so it can never run"; _ph=1; }
grep -q "_craftkit_hook_unregister" "$REPO_DIR/adapters/claude.sh" \
    || { fail "pruning deletes the hook file but leaves its settings.json entry, which points at a missing script"; _ph=1; }
grep -q 'STATE_DIR/claude-hooks' "$REPO_DIR/adapters/claude.sh" \
    || { fail "no hook state file, so the prune pass has no record of what was installed and removes nothing"; _ph=1; }
[[ $_ph -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 29. Drift detector distinguishes clean, drifted and cannot-verify. The third
#     is the point: a context doc records a baseline commit, and this repo
#     squash-merges, so that commit leaves reachable history as soon as its
#     branch merges. A detector that answered "clean" when it cannot see would
#     hand every later claim a false all-clear. Behavioral, in a throwaway repo,
#     because the failure is entirely in how git is asked.
# ---------------------------------------------------------------------------
check "drift detector reports cannot-verify rather than clean"
_dd=0
if ! command -v node >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "    skipped (node or git not on PATH)"
else
    _ddx="$(mktemp -d)"
    (
        cd "$_ddx" && git init -q . && git config user.email t@t && git config user.name t
        echo one > a.txt && echo two > b.txt && git add -A && git commit -qm base
    ) >/dev/null 2>&1
    _base="$(git -C "$_ddx" rev-parse HEAD)"
    _drift() {
        node -e '
const { drift } = require(process.argv[1]);
const r = drift(process.argv[2], process.argv[3], process.argv.slice(4));
console.log(r.state + "|" + r.files.join(",") + "|" + r.reason);' \
            "$REPO_DIR/hooks/craftkit-drift.js" "$_ddx" "$1" "${@:2}"
    }
    [[ "$(_drift "$_base" a.txt)" == clean\|\|* ]] \
        || { fail "drift detector does not report clean when nothing changed"; _dd=1; }
    echo changed > "$_ddx/a.txt"
    [[ "$(_drift "$_base" a.txt)" == "drifted|a.txt|"* ]] \
        || { fail "drift detector misses an edited file, so a stale context doc reads as current"; _dd=1; }
    [[ "$(_drift "$_base" b.txt)" == clean\|\|* ]] \
        || { fail "drift detector reports an untouched file as drifted, which would fire the gate on every file"; _dd=1; }
    # A rename must be reported, not fatal: rev-parse <commit>:<oldpath> dies here.
    (cd "$_ddx" && git checkout -q -- a.txt && git mv b.txt c.txt && git commit -qm rename) >/dev/null 2>&1
    case "$(_drift "$_base")" in
        drifted*) : ;;
        *) fail "drift detector does not report a rename, so a moved file silently reads as unchanged" ; _dd=1 ;;
    esac
    # An unreachable baseline is this repo's normal case after a squash merge.
    # The reason, not just the state: git diff already throws on a bogus sha, so a check
    # asserting only cannot-verify passes with the reachability probe deleted and proves
    # nothing. The probe exists to say WHY, which is the difference between a diagnosable
    # message and "git diff failed".
    _unreach="$(_drift 0000000000000000000000000000000000000000 a.txt)"
    [[ "$_unreach" == cannot-verify\|\|* ]] \
        || { fail "drift detector answers clean for an unreachable baseline, handing every later claim a false all-clear"; _dd=1; }
    case "$_unreach" in
        *unreachable*squashed*) : ;;
        *) fail "unreachable baseline reports no diagnosable reason, so a permanently blind detector looks like a transient git error"; _dd=1 ;;
    esac
    [[ "$(_drift "" a.txt)" == cannot-verify\|\|* ]] \
        || { fail "drift detector answers clean when no baseline was recorded"; _dd=1; }
    _nogit="$(mktemp -d)"
    [[ "$(node -e '
const { drift } = require(process.argv[1]);
console.log(drift(process.argv[2], "HEAD", ["a.txt"]).state);' "$REPO_DIR/hooks/craftkit-drift.js" "$_nogit")" == "cannot-verify" ]] \
        || { fail "drift detector answers clean outside a git repository"; _dd=1; }
    rm -rf "$_ddx" "$_nogit"
    [[ $_dd -eq 0 ]] && pass
fi

# ---------------------------------------------------------------------------
# 30. A skill's craftkitInject renders, on every tool. Agents and commands render
#     only through the Claude adapter, which is correct: they are the one tool with
#     those hosts. A skill is different, because all four adapters install the same
#     SKILL.md, so leaving the splice in claude.sh would ship Cursor, Gemini and
#     Codex a skill with its core section missing and nothing would say so. Cursor's
#     parallel-review proved the shape: 139 lines against Claude's 255.
#     Two halves, because either alone passes vacuously. The renderer must splice,
#     and the skills pass must call it: a revert to `diff -q "$source_file"` leaves
#     the renderer present, correct, and unreached.
# ---------------------------------------------------------------------------
check "a skill's craftkitInject renders for every tool"
_si=0
_six="$(mktemp -d)"
mkdir -p "$_six/partials" "$_six/rules" "$_six/skills/probe"
cat > "$_six/partials/probe-partial.md" <<'EOF'
---
name: probe-partial
description: fixture
---

PROBE-PARTIAL-BODY
EOF
cat > "$_six/skills/probe/SKILL.md" <<'EOF'
---
name: probe
craftkitInject: probe-partial
---

PROBE-SKILL-BODY
EOF
{
    echo "PARTIALS_DIR='$_six/partials'; RULES_DIR='$_six/rules'; SKILLS_DIR='$_six/skills'"
    sed -n '/^_CRAFTKIT_INJECTED_START=/p;/^_CRAFTKIT_INJECTED_END=/p' "$REPO_DIR/sync.sh"
    sed -n '/^craftkit_inject_list() {/,/^}/p' "$REPO_DIR/sync.sh"
    sed -n '/^craftkit_strip_frontmatter() {/,/^}/p' "$REPO_DIR/sync.sh"
    sed -n '/^craftkit_render_injected() {/,/^}/p' "$REPO_DIR/sync.sh"
    echo 'craftkit_render_injected "$1" "$2"'
} > "$_six/render.sh"
if bash "$_six/render.sh" "$_six/skills/probe/SKILL.md" "$_six/out.md" 2>/dev/null; then
    grep -q 'PROBE-PARTIAL-BODY' "$_six/out.md" \
        || { fail "the shared renderer does not splice a partial into a skill, so an injecting skill installs without its core section"; _si=1; }
    grep -q 'PROBE-SKILL-BODY' "$_six/out.md" \
        || { fail "the shared renderer drops the skill's own body while splicing"; _si=1; }
    [[ "$(head -1 "$_six/out.md")" == "---" ]] \
        || { fail "the shared renderer splices above the frontmatter, so the skill loses its name and never registers"; _si=1; }
    grep -q 'name: probe-partial' "$_six/out.md" \
        && { fail "the shared renderer splices the partial's frontmatter as body text"; _si=1; }
else
    fail "sync.sh no longer exposes craftkit_render_injected as a tool-agnostic function, so only Claude can render an injected skill"
    _si=1
fi
# The skills pass has to reach it. Structural on purpose: the loop's job is choosing what
# to diff and install, and only the source text says which of the two it passes on.
_skills_loop="$(awk '/^sync_adapter\(\) \{/,/^\}/' "$REPO_DIR/sync.sh")"
case "$_skills_loop" in
    *'craftkit_render_injected "$source_file" "$rendered"'*) : ;;
    *) fail "sync_adapter installs SKILL.md without rendering, so a skill's craftkitInject is silently dropped on every tool"; _si=1 ;;
esac
case "$_skills_loop" in
    *'"install_${adapter}_skill" "$skill" "$rendered"'*) : ;;
    *) fail "sync_adapter renders but installs the raw source, so the rendered block never reaches any tool"; _si=1 ;;
esac
rm -rf "$_six"
[[ $_si -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 31. The eval rubric's weights sum to 100, in both places they are written.
#     A percentage is only meaningful against a known total, so a weight edit
#     that lands on 95 or 110 produces a score that looks authoritative and is
#     wrong, silently, forever. The README repeats the table for the reader, so
#     it is checked against the partial the judge actually scores by: a reader
#     trusting a stale README is the same defect one layer out.
# ---------------------------------------------------------------------------
check "eval rubric weights sum to 100, partial and README agree"
_ev=0
_ev_weights() {
    awk -F'|' '
        $2 ~ /^ *(Spec conformance|Correctness|Pattern adherence|Verification|Simplicity) *$/ &&
        $3 ~ /^ *[0-9]+ *$/ { s += $3; n++ }
        END { print s " " n }
    ' "$1"
}
_ev_p="$(_ev_weights "$REPO_DIR/partials/eval-rubric.md")"
_ev_r="$(_ev_weights "$REPO_DIR/README.md")"
[[ "$_ev_p" == "100 5" ]] \
    || { fail "partials/eval-rubric.md weights read '$_ev_p' (want '100 5'), so /eval reports a percentage against the wrong total"; _ev=1; }
[[ "$_ev_r" == "100 5" ]] \
    || { fail "the eval rubric table in README.md reads '$_ev_r' (want '100 5'), so the documented weights differ from the ones the judge scores by"; _ev=1; }
# The awk recompute in skills/eval is the third copy of the weights, and the one that
# produces the number, so it is the copy that matters most and the easiest to miss.
_ev_awk="$(awk -F'[()]' '/s\*[0-9]+ \+ c\*[0-9]+/{print $0}' "$REPO_DIR/skills/eval/SKILL.md")"
case "$_ev_awk" in
    *"s*35 + c*25 + p*20 + v*15 + x*5"*) : ;;
    *) fail "the awk recompute in skills/eval/SKILL.md no longer carries the rubric weights 35/25/20/15/5, so /eval computes a total the rubric does not describe"; _ev=1 ;;
esac
# The partial is the single source only while both hosts inject it.
for _evh in "$REPO_DIR/skills/eval/SKILL.md" "$REPO_DIR/agents/eval-judge.md"; do
    grep -q '^craftkitInject:.*eval-rubric' "$_evh" \
        || { fail "$(basename "$(dirname "$_evh")")/$(basename "$_evh") no longer injects eval-rubric, so it scores by a copied rubric that will drift"; _ev=1; }
done
[[ $_ev -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 32. Intent lives per feature, and every reader of it resolves the same way.
#     ADR-0001 names this as the release-completion condition: while any skill
#     still writes the old shared PLANNING block, intent has two possible homes
#     and a missed writer splits it across both silently, which is worse than
#     the single-slot bug because it is quiet rather than destructive.
# ---------------------------------------------------------------------------
check "intent is per-feature, and its readers share one resolver"
_pl=0
# The old shared block. Its phrase is what every writer and reader used to say.
_pl_hits="$(grep -rln "PLANNING block" "$REPO_DIR/skills" "$REPO_DIR/commands" \
    "$REPO_DIR/partials" "$REPO_DIR/rules" "$REPO_DIR/agents" 2>/dev/null || true)"
[[ -z "$_pl_hits" ]] \
    || { fail "still writing or reading the shared PLANNING block: $(echo "$_pl_hits" | tr '\n' ' ')- intent then has two homes and a missed writer splits it silently"; _pl=1; }
# The generator must not carry the marker in its own output template, or it
# recreates the shared block on the next regenerate.
_pl_tmpl="$(awk '/^```markdown/,/^```$/' "$REPO_DIR/skills/fe-context/SKILL.md")"
case "$_pl_tmpl" in
    *"BEGIN PLANNING"*) fail "skills/fe-context still emits a BEGIN PLANNING marker in its template, so regenerating recreates the shared intent slot"; _pl=1 ;;
esac
# One resolver, injected by everything that touches intent. A second copy of the
# glob rule is how two skills come to disagree about which feature is active.
[[ -f "$REPO_DIR/partials/planning-resolve.md" ]] \
    || { fail "partials/planning-resolve.md is missing, so each intent skill resolves the active feature its own way"; _pl=1; }
for _pls in spec plan adr docs eval fe-test android-test ios-test; do
    grep -q '^craftkitInject:.*planning-resolve' "$REPO_DIR/skills/$_pls/SKILL.md" \
        || { fail "skills/$_pls does not inject planning-resolve, so it resolves the active feature by its own rule"; _pl=1; }
done
# The orchestrators name "the resolved intent file" to their agents, so they must carry the
# resolver too; citing it by name without injecting it left each to improvise the glob.
for _plc in build parallel-build parallel-review parallel-ship team-build; do
    grep -q '^craftkitInject:.*planning-resolve' "$COMMANDS_DIR/$_plc.md" \
        || { fail "commands/$_plc does not inject planning-resolve, so it resolves the active feature by its own rule"; _pl=1; }
done
# Behavioral: a feature's .tests.md sits beside its intent file, so the resolver's own glob
# must still find exactly one candidate, even if a status: line reaches column 0 there.
_pl_glob="$(grep -m1 '^rtk grep -l "^status: active"' "$REPO_DIR/partials/planning-resolve.md" | sed 's/^rtk //')"
_pl_fx="$(mktemp -d)"
mkdir -p "$_pl_fx/docs/planning"
printf -- '---\nslug: a\nstatus: active\n---\n' > "$_pl_fx/docs/planning/a.md"
printf -- '---\nfeature: a\n---\nstatus: active\n' > "$_pl_fx/docs/planning/a.tests.md"
_pl_n="$(cd "$_pl_fx" && bash -c "$_pl_glob" | grep -c . || true)"
rm -rf "$_pl_fx"
[[ -n "$_pl_glob" && "$_pl_n" == "1" ]] \
    || { fail "planning-resolve's glob found ${_pl_n:-no} candidates for one feature with a .tests.md beside it, so every feature with test cases resolves as ambiguous"; _pl=1; }
# Nothing may record the branch-to-feature mapping; it is derived (ADR-0001).
grep -rn "status: active" "$REPO_DIR/partials/planning-resolve.md" >/dev/null \
    || { fail "planning-resolve no longer globs on status, so the mapping has to be recorded somewhere and will go stale"; _pl=1; }
[[ $_pl -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 32b. Test cases have one reader contract. Every skill that builds, plans, tests or
#      scores against a feature's test cases injects the same partial, so "approved
#      only" and "never derived from the diff" cannot drift between consumers.
# ---------------------------------------------------------------------------
check "test-case consumers share one contract"
_tc=0
[[ -f "$PARTIALS_DIR/test-cases-resolve.md" ]] \
    || { fail "partials/test-cases-resolve.md is missing, so each consumer decides which test cases count on its own"; _tc=1; }
grep -q "never from the diff" "$PARTIALS_DIR/test-cases-resolve.md" 2>/dev/null \
    || { fail "test-cases-resolve no longer forbids deriving cases from the diff, so tests can be rewritten to confirm the implementation"; _tc=1; }
for _tcs in plan fe-test android-test ios-test eval; do
    grep -q '^craftkitInject:.*test-cases-resolve' "$SKILLS_DIR/$_tcs/SKILL.md" \
        || { fail "skills/$_tcs does not inject test-cases-resolve, so it reads test cases by its own rule"; _tc=1; }
done
# The judge is a cold agent: injecting into /eval alone never reaches it, so the spawn
# template itself must carry the cases.
grep -q '^TEST CASES:' "$SKILLS_DIR/eval/SKILL.md" \
    || { fail "skills/eval's judge template has no TEST CASES field, so eval-judge scores without the approved cases"; _tc=1; }
for _tcc in build parallel-build team-build; do
    grep -q '^craftkitInject:.*test-cases-resolve' "$COMMANDS_DIR/$_tcc.md" \
        || { fail "commands/$_tcc does not inject test-cases-resolve, so it builds to test cases by its own rule"; _tc=1; }
done
[[ $_tc -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 33. Derived context is derived, never stored (ADR-0002). A reader that still
#     names the old file is reading a snapshot the generator stopped writing,
#     which returns nothing rather than failing loudly. Release 1's narrower
#     grep on the phrase "PLANNING block" missed two writers for exactly this
#     reason, so this one matches the path itself.
# ---------------------------------------------------------------------------
check "derived context is derived, not stored"
_dc=0
_dc_hits="$(grep -rn "docs/context\.md" "$REPO_DIR/skills" "$REPO_DIR/commands" \
    "$REPO_DIR/rules" "$REPO_DIR/agents" "$REPO_DIR/partials" "$REPO_DIR/hooks" 2>/dev/null \
    | grep -v "is migrated, then deleted" || true)"
[[ -z "$_dc_hits" ]] \
    || { fail "source still treats docs/context.md as a stored doc: $(echo "$_dc_hits" | sed "s|$REPO_DIR/||" | cut -d: -f1-2 | tr '\n' ' ')- the generator no longer writes it, so the read silently returns nothing"; _dc=1; }
# The three generators must emit, not write.
for _g in fe android ios; do
    # Heading-anchored: the phrase also appears in the inline plan, so an
    # unanchored grep passes while the actual write step is renamed back.
    grep -qE "^## Step [0-9]+: Emit the derived context" "$SKILLS_DIR/$_g-context/SKILL.md" \
        || { fail "skills/$_g-context renamed its emit step; a generator that writes recreates the stale cache ADR-0002 removed"; _dc=1; }
    grep -qE "No file written|writing no file|Write no file" "$SKILLS_DIR/$_g-context/SKILL.md" \
        || { fail "skills/$_g-context does not state that it writes no file, so a reader cannot tell the output is not persisted"; _dc=1; }
done
[[ $_dc -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 34. Every parallel orchestrator passes full file contents to its agents, so
#     the always-on claim in rules/grounding.md stays true. It shipped false for
#     two of three: parallel-review and parallel-ship passed a diff only, while
#     the rule told agents a gap in the payload is a gap to name. Holding read
#     tools and no contents, they read instead, and each read is a round-trip
#     that re-sends the agent's whole growing context. Observed at 63-75k input
#     per agent on a three-agent review.
# ---------------------------------------------------------------------------
check "parallel orchestrators pass file contents, as grounding promises"
_pc=0
grep -q "pass full file contents" "$REPO_DIR/rules/grounding.md" \
    || { fail "rules/grounding.md no longer promises full file contents; either restore it or drop check 34, because the two must agree"; _pc=1; }
for _o in parallel-review parallel-ship parallel-build; do
    grep -q "full file contents" "$REPO_DIR/commands/$_o.md" \
        || { fail "commands/$_o.md does not pass full file contents, so its agents read files themselves and each read re-bills their whole context"; _pc=1; }
done
[[ $_pc -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 35. The read cap rewrites an uncapped whole-file read and leaves everything
#     else alone. Behavioral, because a grep cannot tell a cap that fires from
#     one that does not, and the two failure directions cost opposite things: no
#     cap means a 2000-line file lands whole and is re-sent every turn after,
#     while a cap on `cat f | wc -l` makes the command report 400 and lie. The
#     fail-open cases are here for the same reason as check 23: a hook that
#     guesses on malformed stdin is worse than one that abstains.
# ---------------------------------------------------------------------------
check "the read cap fires on big reads only"
_rc=0
_rch="$REPO_DIR/hooks/craftkit-read-cap.js"
if [[ ! -f "$_rch" ]]; then
    fail "hooks/craftkit-read-cap.js is gone, so every whole-file read lands uncapped again"
    _rc=1
else
    _rcx="$(mktemp -d)"
    awk 'BEGIN{for(i=1;i<=2000;i++)print "line "i}' > "$_rcx/big.txt"
    awk 'BEGIN{for(i=1;i<=10;i++)print "line "i}' > "$_rcx/small.txt"
    _rcrun() { printf '%s' "$1" | node "$_rch" 2>/dev/null; }
    # Both command shapes, because the hook shares the Bash event with rtk's own
    # rewrite and cannot choose which updatedInput the merge applies.
    for _shape in "cat $_rcx/big.txt" "rtk read $_rcx/big.txt"; do
        _rcrun "{\"tool_input\":{\"command\":\"$_shape\"},\"cwd\":\"$_rcx\"}" | grep -q '\-m 800' \
            || { fail "read cap does not fire on '$_shape', so a 2000-line file lands whole and is re-sent every turn"; _rc=1; }
    done
    # The cap rides on an undocumented rtk semantic: a file of n lines passes whole when
    # n <= N and shows N/2 when n > N, measured on 0.49.0. An rtk release that changes the
    # ratio would silently halve every big read again, so pin it here rather than in prose.
    if command -v rtk >/dev/null 2>&1; then
        [[ "$(rtk read -m 800 "$_rcx/big.txt" | grep -c '^line [0-9]*$')" == "400" ]] \
            || { fail "rtk read -m 800 no longer shows 400 lines, so hooks/craftkit-read-cap.js CAP is calibrated to the wrong ratio"; _rc=1; }
        [[ "$(rtk read -m 800 "$_rcx/small.txt" | grep -c '^line [0-9]*$')" == "10" ]] \
            || { fail "rtk read -m 800 truncates a file under the threshold, so the cap is no longer free below it"; _rc=1; }
    fi
    for _skip in "cat $_rcx/small.txt" "cat $_rcx/big.txt | wc -l" "rtk read -m 400 $_rcx/big.txt" "cat $_rcx/nope.txt"; do
        [[ "$(_rcrun "{\"tool_input\":{\"command\":\"$_skip\"},\"cwd\":\"$_rcx\"}")" == "{}" ]] \
            || { fail "read cap rewrote '$_skip', which it must leave alone"; _rc=1; }
    done
    [[ "$(_rcrun 'not json')" == "{}" ]] \
        || { fail "read cap does not fail open on malformed stdin"; _rc=1; }
    rm -rf "$_rcx"
fi
[[ $_rc -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 36. The Read gate refuses a whole-file read and passes everything else, and
#     the bulk-read carve-out is stated in both places an agent could read it.
#     Behavioral for the same reason as check 23: a gate that returns {} is
#     indistinguishable from no gate, and this one fails open by design.
#     DENY, not ask, and the decision is asserted here because it is the one
#     gate that departs from the ask-never-deny law: an ask resolves to allow
#     under auto-accept without surfacing, so the gate read as coverage while
#     the file landed anyway. Two skips matter more than the refusal: a read
#     inside a subagent is the bulk-read call the gate offers, and a bounded
#     offset/limit read is the behavior it is asking for, so refusing either
#     would refuse its own advice.
# ---------------------------------------------------------------------------
check "the read gate refuses whole-file reads only"
_rg=0
_rgh="$REPO_DIR/hooks/gate-read-size.js"
if ! command -v node >/dev/null 2>&1; then
    echo "    skipped (node not on PATH)"
elif [[ ! -f "$_rgh" ]]; then
    fail "hooks/gate-read-size.js is gone, so a whole-file Read lands uncapped and is re-sent every turn after"
    _rg=1
else
    _rgx="$(mktemp -d)"
    awk 'BEGIN{for(i=1;i<=2000;i++)print "line "i}' > "$_rgx/big.txt"
    awk 'BEGIN{for(i=1;i<=10;i++)print "line "i}' > "$_rgx/small.txt"
    python3 - "$_rgx" << 'PYEOF'
import json, sys
rgx = sys.argv[1]
def u(c, **kw):
    e = {"type": "user", "message": {"role": "user", "content": c}}; e.update(kw); return e
def a(items, **kw):
    e = {"type": "assistant", "message": {"role": "assistant", "content": items}}; e.update(kw); return e
read = [{"type": "tool_use", "name": "Read", "input": {"file_path": rgx + "/big.txt"}}]
open(rgx + "/plain.jsonl", "w").write("\n".join(json.dumps(x) for x in [u("read it"), a(read)]) + "\n")
# A subagent turn carries isSidechain, and it is the bulk-read call the gate offers.
open(rgx + "/side.jsonl", "w").write("\n".join(json.dumps(x) for x in
    [u("read it", isSidechain=True), a(read, isSidechain=True)]) + "\n")
PYEOF
    _rgrun() { printf '%s' "$1" | node "$_rgh" 2>/dev/null; }
    # Unique per run even though this gate no longer keeps a turn budget: the ids stay
    # distinct so a future budget cannot make the check pass once and fail every run after,
    # which is exactly what happened while the gate still asked.
    _rgs="rgs-$$-${RANDOM}"
    _rgin() { printf '{"tool_input":%s,"transcript_path":"%s","session_id":"%s"}' "$1" "$_rgx/$2" "$_rgs-$3"; }

    _rgrun "$(_rgin "{\"file_path\":\"$_rgx/big.txt\"}" plain.jsonl a1)" | grep -q '"permissionDecision":"deny"' \
        || { fail "read gate does not refuse a 2000-line whole-file Read, so the file lands and is re-sent every turn after"; _rg=1; }
    # Every large read in the turn, not just the first. The other gates spend one prompt per
    # turn so a ten-edit turn does not train the click-through, but this one shows no prompt,
    # so a budget here would buy nothing and let the 2nd through Nth large read land.
    _rgrun "$(_rgin "{\"file_path\":\"$_rgx/big.txt\"}" plain.jsonl a1)" | grep -q '"permissionDecision":"deny"' \
        || { fail "read gate refuses only the first large read of a turn, so every one after it lands whole"; _rg=1; }
    # The refusal has to carry the way out, or it is a dead end the model retries into.
    _reason="$(_rgrun "$(_rgin "{\"file_path\":\"$_rgx/big.txt\"}" plain.jsonl a1)")"
    for _path in 'bulk-read' 'offset' 'limit' 'CRAFTKIT_READ_GATE=off'; do
        case "$_reason" in
            *"$_path"*) ;;
            *) fail "the read gate's refusal does not name '$_path', so it refuses without offering the way through"; _rg=1 ;;
        esac
    done
    for _case in "{\"file_path\":\"$_rgx/small.txt\"}|plain.jsonl|b1" \
                 "{\"file_path\":\"$_rgx/big.txt\",\"limit\":200}|plain.jsonl|b2" \
                 "{\"file_path\":\"$_rgx/big.txt\",\"offset\":50}|plain.jsonl|b3" \
                 "{\"file_path\":\"$_rgx/big.png\"}|plain.jsonl|b4" \
                 "{\"file_path\":\"$_rgx/nope.txt\"}|plain.jsonl|b5" \
                 "{\"file_path\":\"$_rgx/big.txt\"}|side.jsonl|b6"; do
        _ti="${_case%%|*}"; _rest="${_case#*|}"; _tr="${_rest%%|*}"; _sid="${_rest##*|}"
        [[ "$(_rgrun "$(_rgin "$_ti" "$_tr" "$_sid")")" == "{}" ]] \
            || { fail "read gate asks on '$_ti' ($_tr), which it must pass"; _rg=1; }
    done
    [[ "$(_rgrun 'not json')" == "{}" ]] \
        || { fail "read gate does not fail open on malformed stdin"; _rg=1; }
    rm -rf "$_rgx" "${TMPDIR:-/tmp}/craftkit-gate/$_rgs"-*.readsize
fi
# The carve-out has two homes because a cold agent carries the partial, not the rule, and
# the rule is what a human reads. Either one alone leaves bulk-read looking like a violation.
[[ -f "$REPO_DIR/agents/bulk-read.md" ]] \
    || { fail "agents/bulk-read.md is gone, but gate-read-size.js still offers it as the cheaper path"; _rg=1; }
for _f in rules/grounding.md partials/grounding-claims.md; do
    grep -q 'bulk-read' "$REPO_DIR/$_f" \
        || { fail "$_f does not name the bulk-read exception, so the one agent whose job is reading unhanded files reads as a violation of it"; _rg=1; }
done
[[ $_rg -eq 0 ]] && pass

echo
if [[ $FAILURES -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "$FAILURES check(s) failed."
exit 1
