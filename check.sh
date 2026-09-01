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
# 8. No always-active rule claims docs/context.md is universal.
#    Native single-screen skills declare they do not use it. An absolute claim in
#    an always-on rule contradicts them on every native turn.
# ---------------------------------------------------------------------------
check "no absolute docs/context.md claim"
_abs="$(grep -rn "docs/context.md" "$RULES_DIR" 2>/dev/null \
    | grep -E "mandatory, not optional|no exceptions|always read .*mandatory" || true)"
if [[ -n "$_abs" ]]; then
    echo "$_abs" | while IFS= read -r l; do echo "    FAIL: absolute claim contradicts native skills: ${l#$REPO_DIR/}"; done
    FAILURES=$((FAILURES + 1))
else
    pass
fi

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


def build(mode):
    lines = [{"type": "user", "message": {"role": "user", "content": "edit foo"}}]
    if mode == "skill":
        lines.append(assistant([use("Skill", {"skill": "fe-test"})]))
    lines.append(assistant([use("Edit", {"file_path": "/x/ViewFoo.tsx"})]))
    # A tool_result also has role user, and must not be read as a new turn.
    lines.append({"type": "user", "message": {"role": "user",
                  "content": [{"type": "tool_result", "content": "ok"}]}})
    if mode == "verified":
        lines.append(assistant([use("Bash", {"command": "rtk tsc --noEmit && rtk lint ViewFoo.tsx"})]))
    return lines


for mode in ("bare", "skill", "verified"):
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
        printf '{"session_id":"s","transcript_path":"%s","cwd":"%s"%s}' "$1" "$_gx/proj" "${2:-}" \
            | node "$REPO_DIR/hooks/gate-verify-on-stop.js" 2>/dev/null
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
    _stopgate "$_gx/bare.jsonl" | grep -q '"decision":"block"' \
        || { fail "stop gate let a turn end with edits and no verification command"; _gd=1; }
    _stopgate "$_gx/verified.jsonl" | grep -q '"decision"' \
        && { fail "stop gate blocks after the gates ran, which makes ending any turn impossible"; _gd=1; }
    _stopgate "$_gx/bare.jsonl" ',"stop_hook_active":true' | grep -q '"decision"' \
        && { fail "stop gate re-blocks while already active, so the agent cannot ever stop"; _gd=1; }
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
        # Delegating the edits hides them the same way the shell does: a subagent's writes
        # land in ITS transcript, so the parent's turn shows no edits at all.
        _stopgate "$_gx/delegated.jsonl" | grep -q '"decision":"block"' \
            || { fail "stop gate misses edits made by a spawned agent, so delegating skips verification"; _gd=1; }
    fi
    mkdir -p "$_gx/proj/.claude/skills/zzz-fixture-skill"
    _announcegate() {
        printf '{"session_id":"s","transcript_path":"%s","cwd":"%s"%s}' "$1" "$_gx/proj" "${2:-}" \
            | node "$REPO_DIR/hooks/gate-announce-honored.js" 2>/dev/null
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
    _announcegate "$_gx/announce-lied.jsonl" ',"stop_hook_active":true' | grep -q '"decision"' \
        && { fail "announce gate re-blocks while already active, so the agent cannot ever stop"; _gd=1; }
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

    for _g in gate-skill-first.js gate-verify-on-stop.js gate-announce-honored.js; do
        echo 'not json' | node "$REPO_DIR/hooks/$_g" >/dev/null 2>&1 \
            || { fail "$_g exits non-zero on malformed stdin, which surfaces as a tool error every call"; _gd=1; }
    done
    rm -rf "$_gx"
    [[ $_gd -eq 0 ]] && pass
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

echo
if [[ $FAILURES -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "$FAILURES check(s) failed."
exit 1
