#!/usr/bin/env bash
# Content integrity checks for craftkit source. There is no build or test suite here —
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
#    a subagent that does not exist — the orchestrator degrades silently.
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
        fail "skills/$s/ and commands/${s}.md both install to <tool>/commands/${s}.md — delete one"
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
# 5. Every craftkitInject name resolves.
#    An injecting agent whose source is renamed loses its whole checklist and
#    still installs — a review agent with nothing to review by.
# ---------------------------------------------------------------------------
check "craftkitInject sources resolve"
_inj=0
for a in $(agent_names); do
    _list="$(awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^craftkitInject:/{sub(/^craftkitInject:[[:space:]]*/,"");print;exit}' "$AGENTS_DIR/$a.md")"
    [[ -z "$_list" ]] && continue
    for n in $(echo "$_list" | tr ',' ' '); do
        if [[ ! -f "$RULES_DIR/${n}.md" && ! -f "$SKILLS_DIR/${n}/SKILL.md" ]]; then
            fail "agents/$a.md injects '$n' — not in rules/ or skills/"
            _inj=1
        fi
    done
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
        fail "hook advertises /$n — no such skill or command"
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
_exempt_platform="define"   # pre-code planning only — no platform surface
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
    fail "package.json=$_pkg  README header=$_hdr  CHANGELOG.md newest=$_log — must match"
fi

# ---------------------------------------------------------------------------
# 11. Routing hook resolves each platform from cwd, and survives bad stdin.
#     Platform used to be the model's job to infer from filenames, which is how
#     a /fe-* skill got announced on a .kt task. It is now injected per prompt —
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
        || { fail "hook exits non-zero on malformed stdin — gate disappears every prompt"; _pd=1; }
    rm -rf "$_fx"
    [[ $_pd -eq 0 ]] && pass
fi

# ---------------------------------------------------------------------------
# 12. Every hook command ensure_tools registers resolves under a stripped PATH.
#     Hooks spawn with /usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:. — no homebrew,
#     no fnm — so a bare `rtk hook claude` died with "rtk: command not found".
#     Non-blocking, so it degraded silently: every Bash call ran unrewritten and
#     the whole token filter was off with nothing but a dim hook error to show it.
#     `rtk init` rewrites the entry to bare on each run, hence the re-absolutize.
# ---------------------------------------------------------------------------
check "rtk hook is absolutized after rtk init"
if ! grep -q '_rtk_hook_absolutize$' sync.sh; then
    fail "ensure_tools does not call _rtk_hook_absolutize — bare 'rtk hook claude' fails under the hooks' stripped PATH"
elif ! grep -q '_rtk_hook_absolutize()' sync.sh; then
    fail "_rtk_hook_absolutize is called but never defined"
else
    pass
fi

# ---------------------------------------------------------------------------
# 13. Every name in ADAPTERS has a sourced adapter file, and every adapter file is
#     listed. sync.sh calls adapter functions by string interpolation, so a name with
#     no sourced file dies at the first call — mid-sync, after some tools are already
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
    case " $_live " in *" $_an "*) ;; *) fail "adapters/${_an}.sh exists but is not in ADAPTERS — delete it or list it"; _ad=1 ;; esac
done
[[ $_ad -eq 0 ]] && pass

# ---------------------------------------------------------------------------
# 14. The routing hook's node path is absolute and not version-pinned.
#     Hooks spawn under a stripped PATH with no profile, so the command must carry an
#     absolute interpreter — and it must be one that survives, because a dead
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
        *)  fail "_resolve_node_bin returned non-absolute '$_nb' — hooks get a stripped PATH" ;;
    esac
fi

# ---------------------------------------------------------------------------
# 15. Every parallel-* orchestrator has a sequential twin, named in both channels.
#     A parallel-* command exists to spawn agents, so a context that cannot spawn
#     them cannot run one — a subagent, or a session that disables spawning. With
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

echo
if [[ $FAILURES -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "$FAILURES check(s) failed."
exit 1
