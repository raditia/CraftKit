#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || [[ "${BASH_VERSINFO[0]}" -eq 3 && "${BASH_VERSINFO[1]}" -lt 2 ]]; then
    echo "Error: bash 3.2+ required (got ${BASH_VERSION})"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.craftkit-state"
RULES_DIR="$REPO_DIR/rules"
SKILLS_DIR="$REPO_DIR/skills"
COMMANDS_DIR="$REPO_DIR/commands"
AGENTS_DIR="$REPO_DIR/agents"
PARTIALS_DIR="$REPO_DIR/partials"

mkdir -p "$STATE_DIR"

# Downgrade guard. The state files record names only, so syncing from a checkout older
# than what is installed uninstalls the newer rules and says nothing about it: a
# one-commit-stale main removed the flag-safety rule from all four tools this way. Refuse
# instead, because "your rules silently reverted" is not a diagnosable symptom.
# Version comparison is numeric per dot-segment so 1.9.0 stays below 1.10.0.
_ck_version_file="$STATE_DIR/version"
_ck_repo_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_DIR/package.json" | head -1)"

_ck_version_lt() {
    # 0 (true) when $1 is strictly older than $2. sort -V does the version ordering,
    # and this repo already depends on it for the same job (adapters/claude.sh).
    [[ "$1" == "$2" ]] && return 1
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

if [[ -n "$_ck_repo_version" && -f "$_ck_version_file" && -z "${CRAFTKIT_ALLOW_DOWNGRADE:-}" ]]; then
    _ck_installed="$(head -1 "$_ck_version_file" | tr -d '[:space:]')"
    if [[ -n "$_ck_installed" ]] && _ck_version_lt "$_ck_repo_version" "$_ck_installed"; then
        echo "Refusing to sync: this checkout is older than what is installed." >&2
        echo "  installed: v$_ck_installed" >&2
        echo "  this tree: v$_ck_repo_version" >&2
        echo "Syncing would uninstall every rule, skill, command and agent added since" >&2
        echo "v$_ck_repo_version, with no other signal that it happened." >&2
        echo "Fix: git pull, then sync again. Override: CRAFTKIT_ALLOW_DOWNGRADE=1" >&2
        exit 1
    fi
fi

# User choices live in one key=value file beside the state files, because the post-merge
# hook syncs without the caller's environment and an opt-in a git pull silently undid
# would not be one. Precedence: env var > config file > built-in default. An empty default
# means unset, which keeps each tool's own default (gates.director: Claude on, Codex off).
# Resolved after the downgrade guard, so a refused sync never flips anything.
CRAFTKIT_CONFIG="$STATE_DIR/config"
_CK_KEYS=(
    "humanizer%on%humanizer skill, standalone (/pr-message and /docs use /clarity)"
    "playwright%off%Playwright CLI and its agent skill (needs npm and Node 20+)"
    "dashboard%off%agent dashboard, logs tool calls to ~/.craftkit/agent-tree"
    "gates.routing%%routing gates: skill-first and announce hooks, routing rule prose"
    "gates.director%%director gate: delegate 3+ file edits (unset: Claude on, Codex off)"
    "gates.verify%%verify gate: Stop hook blocks a turn that edited without verifying"
)

_ck_bool() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        1|on|true|yes) echo on ;;
        0|off|false|no) echo off ;;
    esac
}

_ck_var() { echo "CK_${1//./_}"; }

_ck_known() {
    local e
    for e in "${_CK_KEYS[@]}"; do [[ "${e%%\%*}" == "$1" ]] && return 0; done
    return 1
}

# Each distinct warning prints once per run, so --configure's second resolve repeats none.
_CK_WARNED=""
_ck_warn() {
    printf '%s\n' "$_CK_WARNED" | grep -qxF -- "$1" && return 0
    _CK_WARNED="$_CK_WARNED"$'\n'"$1"
    echo "Warning: $1" >&2
}

# Rewrites the config with key dropped, then key=value appended when a value is given.
# Every other line, comments and unknown keys included, is kept as the user wrote it.
# Written beside the config and moved over it, so an interrupted sync never leaves half a
# file; mktemp creates it 0600, which the move carries over.
craftkit_config_set() {
    local tmp
    tmp="$(mktemp "$STATE_DIR/config.XXXXXX")"
    [[ -f "$CRAFTKIT_CONFIG" ]] && awk -F= -v k="$1" '{ kk=$1; gsub(/[[:space:]]/, "", kk) } kk != k' "$CRAFTKIT_CONFIG" > "$tmp"
    [[ -n "${2:-}" ]] && echo "$1=$2" >> "$tmp"
    mv "$tmp" "$CRAFTKIT_CONFIG"
}

# Runtime gate choices match the rendered install until the next sync resolves them again.
_ck_save_state() {
    local k var
    # Hooks read gate choices at runtime from one file per gate, present only when the
    # gate is set explicitly, so an absent file is unset and each tool keeps its default.
    for k in routing director verify; do
        var="$(_ck_var "gates.$k")"
        if [[ -n "${!var}" ]]; then
            [[ "$(cat "$STATE_DIR/gate-$k" 2>/dev/null)" == "${!var}" ]] || echo "${!var}" > "$STATE_DIR/gate-$k"
        else
            rm -f "$STATE_DIR/gate-$k"
        fi
    done
    # ponytail: mirrors dashboard into the v1.56-v1.58 state file so a rollback to v1.58.0 keeps the dashboard. ceiling: two files hold one choice. upgrade: drop this write two releases after 1.59.0.
    if [[ "$CK_dashboard" == on ]]; then
        [[ -s "$STATE_DIR/dashboard" ]] || echo "mirror of dashboard=on in config" > "$STATE_DIR/dashboard"
    else
        rm -f "$STATE_DIR/dashboard"
    fi
}

# After the checklist, pass --after-checklist: the env alias must not overwrite an answer.
craftkit_config_resolve() {
    local e key var val line k v env
    for e in "${_CK_KEYS[@]}"; do
        key="${e%%\%*}"; val="${e#*%}"
        printf -v "$(_ck_var "$key")" '%s' "${val%%\%*}"
    done
    # flag: CRAFTKIT_DASHBOARD (env alias of dashboard). off: no agent-log hook, status line or ccdash installed, and a sync removes any left from when it was on, logs included. remove: if the dashboard ever becomes default-on.
    # v1.56 to v1.58 recorded the opt-in as an empty state file; it becomes a config line once.
    # The non-empty mirror _ck_save_state writes is not an opt-in to migrate.
    if [[ -f "$STATE_DIR/dashboard" && ! -s "$STATE_DIR/dashboard" ]]; then
        grep -Eq '^[[:space:]]*dashboard[[:space:]]*=' "$CRAFTKIT_CONFIG" 2>/dev/null || craftkit_config_set dashboard on
    fi
    # The legacy alias persists its value, as it always did, so a git pull keeps the opt-in.
    if [[ -n "${CRAFTKIT_DASHBOARD:-}" && "${1:-}" != --after-checklist ]]; then
        val="$(_ck_bool "$CRAFTKIT_DASHBOARD")"
        if [[ -n "$val" ]]; then
            craftkit_config_set dashboard "$val"
        else
            _ck_warn "CRAFTKIT_DASHBOARD=$(printf '%q' "$CRAFTKIT_DASHBOARD") not understood (use 1 or 0); dashboard setting unchanged"
        fi
    fi
    if [[ -f "$CRAFTKIT_CONFIG" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" || "$line" == \#* ]] && continue
            k="${line%%=*}"; v="${line#*=}"
            k="${k//[[:space:]]/}"; v="$(_ck_bool "${v//[[:space:]]/}")"
            if [[ "$line" != *=* ]] || ! _ck_known "$k" || [[ -z "$v" ]]; then
                _ck_warn "~/.craftkit-state/config: $(printf '%q' "${line:0:80}") not understood (known keys take on or off); ignored, prior setting kept"
                continue
            fi
            printf -v "$(_ck_var "$k")" '%s' "$v"
        done < "$CRAFTKIT_CONFIG"
    fi
    # Overrides affect the install and runtime gates, but leave the saved config unchanged.
    for e in "${_CK_KEYS[@]}"; do
        key="${e%%\%*}"
        [[ "$key" == dashboard ]] && continue
        env="CRAFTKIT_$(echo "$key" | tr '.[:lower:]' '_[:upper:]')"
        [[ -n "${!env:-}" ]] || continue
        val="$(_ck_bool "${!env}")"
        if [[ -n "$val" ]]; then
            printf -v "$(_ck_var "$key")" '%s' "$val"
        else
            _ck_warn "$env=$(printf '%q' "${!env}") not understood (use on or off); ignored"
        fi
    done
    _ck_save_state
    CRAFTKIT_DASHBOARD_ON=0
    [[ "$CK_dashboard" == on ]] && CRAFTKIT_DASHBOARD_ON=1
    return 0
}

# The checklist: one line per toggle with its current value. Only on a terminal, so
# postinstall, post-merge and CI never block on a prompt nobody can see.
craftkit_configure() {
    if [[ ! -t 0 ]]; then
        echo "    --configure needs a terminal; config left as is"
        return 0
    fi
    local e key label var cur ans val
    echo "Choose what craftkit installs and enforces. Enter keeps a value; type on or off (gates also take unset)."
    for e in "${_CK_KEYS[@]}"; do
        key="${e%%\%*}"; label="${e##*%}"; var="$(_ck_var "$key")"; cur="${!var:-unset}"
        read -r -p "  $key [$cur] $label: " ans || ans=""
        ans="$(printf '%s' "$ans" | tr -d '[:space:]')"
        [[ -z "$ans" ]] && continue
        if [[ "$ans" == unset && "$key" == gates.* ]]; then
            craftkit_config_set "$key"
        elif val="$(_ck_bool "$ans")" && [[ -n "$val" ]]; then
            craftkit_config_set "$key" "$val"
        else
            echo "    '$ans' not understood, $key kept at $cur"
        fi
    done
    [[ -f "$CRAFTKIT_CONFIG" ]] || : > "$CRAFTKIT_CONFIG"
}

craftkit_config_resolve
_ck_configure=0
if [[ "${1:-}" == "--configure" ]]; then
    _ck_configure=1
    craftkit_configure
    craftkit_config_resolve --after-checklist
fi

source "$REPO_DIR/adapters/claude.sh"
source "$REPO_DIR/adapters/cursor.sh"
source "$REPO_DIR/adapters/gemini.sh"
source "$REPO_DIR/adapters/codex.sh"

ADAPTERS=("claude" "cursor" "gemini" "codex")

# Routing drift guard: every skill in skills/ must be named in the routing hook,
# else the skill-first gate silently can't route it. Fail loud before syncing.
# (Sensor for the routing-duplication seam; the curated tables stay hand-authored.)
_routing_hook="$REPO_DIR/hooks/craftkit-routing.js"
if [[ -f "$_routing_hook" ]]; then
    _drift=""
    for _d in "$SKILLS_DIR"/*/; do
        _n="$(basename "$_d")"
        grep -Eq "/$_n([^A-Za-z0-9-]|\$)" "$_routing_hook" || _drift="$_drift $_n"
    done
    if [[ -n "$_drift" ]]; then
        echo "ROUTING DRIFT: skill(s) missing from hooks/craftkit-routing.js:$_drift" >&2
        echo "Add each to the hook's routing list (and rules/using-agent-skills.md) before syncing." >&2
        exit 1
    fi
fi

# Returns 0 if needle is in the remaining args
contains() {
    local needle="$1"; shift
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# Reads installed skill names from state file into a global array _state_skills
read_state() {
    local adapter="$1"
    local state_file="$STATE_DIR/$adapter"
    _state_skills=()
    if [[ -f "$state_file" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] || _state_skills+=("$line")
        done < "$state_file"
    fi
}

# Collects skill names that have a SKILL.md (shared across all adapters)
read_current_skills() {
    _current_skills=()
    if [[ ! -d "$SKILLS_DIR" ]]; then return; fi
    for skill_dir in "$SKILLS_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        if [[ -f "$skill_dir/SKILL.md" ]]; then
            _current_skills+=("$skill_name")
        fi
    done
}

# Collects rule names from rules/*.md
read_current_rules() {
    _current_rules=()
    if [[ ! -d "$RULES_DIR" ]]; then return; fi
    for f in "$RULES_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        _current_rules+=("$(basename "$f" .md)")
    done
}

# Collects agent names from agents/*.md
read_current_agents() {
    _current_agents=()
    if [[ ! -d "$AGENTS_DIR" ]]; then return; fi
    for f in "$AGENTS_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        _current_agents+=("$(basename "$f" .md)")
    done
}

# Collects command names from commands/*.md
read_current_commands() {
    _current_commands=()
    if [[ ! -d "$COMMANDS_DIR" ]]; then return; fi
    for f in "$COMMANDS_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        _current_commands+=("$(basename "$f" .md)")
    done
}

# Injection marker written into installed agents, commands and skills. Renaming it orphans
# every block already on disk, so it stays put (and check.sh exempts it from the em-dash gate).
_CRAFTKIT_INJECTED_START="<!-- BEGIN CRAFTKIT-INJECTED-RULES (managed — regenerated on sync from partials/, rules/ or skills/) -->"
_CRAFTKIT_INJECTED_END="<!-- END CRAFTKIT-INJECTED-RULES -->"

# Prints the raw craftkitInject value from a file's frontmatter, empty when absent.
craftkit_inject_list() {
    awk '
        NR==1 && $0=="---" { infm=1; next }
        infm && $0=="---" { exit }
        infm && /^craftkitInject:/ { sub(/^craftkitInject:[[:space:]]*/, ""); print; exit }
    ' "$1"
}

# Prints a markdown file with its leading YAML frontmatter stripped.
craftkit_strip_frontmatter() {
    awk '
        NR==1 && $0=="---" { infm=1; next }
        infm && $0=="---" { infm=0; next }
        !infm { print }
    ' "$1"
}

# flag: gates.routing / gates.verify / gates.director. off: that group's marked prose is dropped from every tool's installed copy. remove: never, the groups are user choices.
# On, only the CRAFTKIT-GATE-* marker lines go, so output matches a tree without them. The
# CRAFTKIT-DIRECTOR block keeps its markers either way: Cursor and Gemini strip it themselves.
# A dropped block that opened after a blank line takes one following blank line with it.
craftkit_strip_gate_blocks() {
    awk -v r="${CK_gates_routing:-}" -v v="${CK_gates_verify:-}" -v d="${CK_gates_director:-}" '
        function off(g) { return (g == "ROUTING" && r == "off") || (g == "VERIFY" && v == "off") || (g == "DIRECTOR" && d == "off") }
        function bad(m) { printf "Error: %s:%d: %s, so gate prose cannot be stripped safely\n", FILENAME, FNR, m > "/dev/stderr"; failed = 1; exit 1 }
        /^<!-- BEGIN CRAFTKIT-GATE-[A-Z]+ -->$/ { if (blk != "") bad("BEGIN " $3 " inside " blk); blk = $3; g = $3; sub(/^CRAFTKIT-GATE-/, "", g); if (off(g)) { skip = 1; eat = prevblank } next }
        /^<!-- END CRAFTKIT-GATE-[A-Z]+ -->$/ { if (blk != $3) bad("END " $3 " without its BEGIN"); blk = ""; if (skip) { skip = 0; pending = eat } next }
        /^<!-- BEGIN CRAFTKIT-DIRECTOR -->$/ && d == "off" { skip = 1; eat = prevblank; next }
        /^<!-- END CRAFTKIT-DIRECTOR -->$/ && d == "off" { skip = 0; pending = eat; next }
        skip { next }
        pending { pending = 0; if ($0 == "") next }
        { print; prevblank = ($0 == "") }
        END { if (!failed && blk != "") bad("BEGIN " blk " never ends") }
    ' "$1" > "$2" || exit 1
}

# Renders a source file into $out. If it opts in via `craftkitInject: a, b`, the bodies of
# partials/<a>.md / rules/<a>.md / skills/<a>/SKILL.md are spliced in as a managed block
# right after its own frontmatter, so the installed copy carries the live text instead of a
# hand-maintained duplicate. No opt-in -> plain copy.
# Tool-agnostic on purpose: commands and skills render for every adapter, while
# agents render for Claude. A missing injected block leaves an installed workflow incomplete.
craftkit_render_injected() {
    local src="$1" out="$2"
    local list
    list="$(craftkit_inject_list "$src")"
    if [[ -z "$list" ]]; then
        craftkit_strip_gate_blocks "$src" "$out"
        return
    fi

    local block
    block="$(mktemp)"
    {
        echo "$_CRAFTKIT_INJECTED_START"
        echo "$list" | tr ',' '\n' | while IFS= read -r r; do
            r="$(echo "$r" | tr -d '[:space:]')"
            [[ -z "$r" ]] && continue
            # partials/ first: it exists only to be spliced, so a name there is
            # unambiguous. rules/ then wins over skills/ when a name is in both.
            if [[ -f "$PARTIALS_DIR/${r}.md" ]]; then
                echo ""
                craftkit_strip_frontmatter "$PARTIALS_DIR/${r}.md"
            elif [[ -f "$RULES_DIR/${r}.md" ]]; then
                echo ""
                craftkit_strip_frontmatter "$RULES_DIR/${r}.md"
            elif [[ -f "$SKILLS_DIR/${r}/SKILL.md" ]]; then
                echo ""
                craftkit_strip_frontmatter "$SKILLS_DIR/${r}/SKILL.md"
            else
                echo "    ! craftkitInject: '$r' not found in partials/, rules/ or skills/, skipped" >&2
            fi
        done
        echo ""
        echo "$_CRAFTKIT_INJECTED_END"
    } > "$block"

    awk -v blockfile="$block" '
        BEGIN { while ((getline line < blockfile) > 0) blk = blk line "\n" }
        NR==1 && $0=="---" { infm=1; print; next }
        infm && $0=="---" { print; printf "\n%s", blk; infm=0; next }
        { print }
    ' "$src" > "$block.src"
    craftkit_strip_gate_blocks "$block.src" "$out"
    rm -f "$block" "$block.src"
}

sync_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/$adapter"
    local changed=0 skipped=0

    read_state "$adapter"
    local installed_skills=("${_state_skills[@]+"${_state_skills[@]}"}")

    read_current_skills
    local current_skills=("${_current_skills[@]+"${_current_skills[@]}"}")
    # Cursor reads the shared ~/.agents/skills the Codex adapter installs, so it defines no
    # installer. An empty list lets the removal loop take back its older copies.
    declare -f "install_${adapter}_skill" >/dev/null || current_skills=()

    # Remove skills that were installed but are no longer in the repo
    for skill in "${installed_skills[@]+"${installed_skills[@]}"}"; do
        if ! contains "$skill" "${current_skills[@]+"${current_skills[@]}"}"; then
            echo "    - removing: $skill"
            "uninstall_${adapter}_skill" "$skill"
            changed=1
        fi
    done

    # Install or update all current skills (all adapters share SKILL.md).
    # Rendered first, so a skill that declares craftkitInject carries the live partial on
    # every tool. Diffing the rendered text is also what keeps the pass idempotent: without
    # it, a skill whose partial moved on looks unchanged and never re-syncs.
    for skill in "${current_skills[@]+"${current_skills[@]}"}"; do
        local source_file="$SKILLS_DIR/$skill/SKILL.md"
        local dest
        dest="$("get_${adapter}_dest" "$skill")"

        if [[ "$adapter" == "codex" ]] && codex_skill_collision "$skill"; then
            echo "    ! skipped unowned Codex skill: $skill ($dest)" >&2
            skipped=1
            continue
        fi

        local rendered
        rendered="$(mktemp)"
        craftkit_render_injected "$source_file" "$rendered"

        if [[ ! -f "$dest" ]] || ! diff -q "$rendered" "$dest" &>/dev/null; then
            echo "    + installing: $skill"
            "install_${adapter}_skill" "$skill" "$rendered"
            changed=1
        fi
        rm -f "$rendered"
    done

    if [[ $changed -eq 0 && $skipped -eq 0 ]]; then
        echo "    (up to date)"
    fi

    # Persist new state
    printf '%s\n' "${current_skills[@]+"${current_skills[@]}"}" > "$state_file"
}

sync_rules_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/${adapter}-rules"
    local changed=0

    local installed_rules=()
    if [[ -f "$state_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && installed_rules+=("$line")
        done < "$state_file"
    fi

    read_current_rules
    local current_rules=("${_current_rules[@]+"${_current_rules[@]}"}")

    # Remove rules that were installed but no longer exist in rules/
    for rule in "${installed_rules[@]+"${installed_rules[@]}"}"; do
        if ! contains "$rule" "${current_rules[@]+"${current_rules[@]}"}"; then
            echo "    - removing rule: $rule"
            "uninstall_${adapter}_rule" "$rule"
            changed=1
        fi
    done

    # Install or update all current rules
    for rule in "${current_rules[@]+"${current_rules[@]}"}"; do
        # Every tool installs the gate-stripped text, so an off group's prose reaches none of them.
        local source_file
        source_file="$(mktemp)"
        craftkit_strip_gate_blocks "$RULES_DIR/${rule}.md" "$source_file"
        local dest cmp_src cmp_tmp=""
        dest="$("get_${adapter}_rule_dest" "$rule")"
        cmp_src="$source_file"
        # An adapter may transform rules on install (e.g. Cursor injects alwaysApply).
        # If it declares effective_<adapter>_rule_source, diff against the rendered output
        # so the skip-unchanged check stays honest instead of re-syncing every run.
        if declare -f "effective_${adapter}_rule_source" >/dev/null 2>&1; then
            cmp_src="$("effective_${adapter}_rule_source" "$rule" "$source_file")"
            cmp_tmp="$cmp_src"
        fi
        if [[ ! -f "$dest" ]] || ! diff -q "$cmp_src" "$dest" &>/dev/null; then
            echo "    + rule: $rule"
            "install_${adapter}_rule" "$rule" "$source_file"
            changed=1
        fi
        # Guard: only remove a genuine temp, never the source (a future adapter whose
        # effective_ hook returns the real source path must not self-destruct).
        [[ -n "$cmp_tmp" && "$cmp_tmp" != "$source_file" ]] && rm -f "$cmp_tmp"
        rm -f "$source_file"
    done

    [[ $changed -eq 0 ]] && echo "    rules: (up to date)"

    printf '%s\n' "${current_rules[@]+"${current_rules[@]}"}" > "$state_file"
}

sync_agents_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/${adapter}-agents"
    local changed=0 skipped=0

    local installed_agents=()
    if [[ -f "$state_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && installed_agents+=("$line")
        done < "$state_file"
    fi

    read_current_agents
    local current_agents=("${_current_agents[@]+"${_current_agents[@]}"}")

    for agent in "${installed_agents[@]+"${installed_agents[@]}"}"; do
        if ! contains "$agent" "${current_agents[@]+"${current_agents[@]}"}"; then
            echo "    - removing agent: $agent"
            "uninstall_${adapter}_agent" "$agent"
            changed=1
        fi
    done

    for agent in "${current_agents[@]+"${current_agents[@]}"}"; do
        local source_file="$AGENTS_DIR/${agent}.md"
        local dest cmp_src cmp_tmp=""
        dest="$("get_${adapter}_agent_dest" "$agent")"
        if [[ "$adapter" == "codex" ]] && codex_agent_collision "$agent"; then
            echo "    ! skipped unowned Codex agent: $agent ($dest)" >&2
            skipped=1
            continue
        fi
        cmp_src="$source_file"
        # An adapter may transform agents on install (e.g. Claude splices craftkitInject
        # rules). If it declares effective_<adapter>_agent_source, diff against the rendered
        # output so the skip-unchanged check stays honest instead of re-syncing every run.
        if declare -f "effective_${adapter}_agent_source" >/dev/null 2>&1; then
            cmp_src="$("effective_${adapter}_agent_source" "$agent" "$source_file")"
            cmp_tmp="$cmp_src"
        fi
        if [[ ! -f "$dest" ]] || ! diff -q "$cmp_src" "$dest" &>/dev/null; then
            echo "    + agent: $agent"
            "install_${adapter}_agent" "$agent" "$source_file"
            changed=1
        fi
        # Guard: only remove a genuine temp, never the source (a future adapter whose
        # effective_ hook returns the real source path must not self-destruct).
        [[ -n "$cmp_tmp" && "$cmp_tmp" != "$source_file" ]] && rm -f "$cmp_tmp"
    done

    [[ $changed -eq 0 && $skipped -eq 0 ]] && echo "    agents: (up to date)"

    printf '%s\n' "${current_agents[@]+"${current_agents[@]}"}" > "$state_file"
}

sync_commands_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/${adapter}-commands"
    local changed=0 skipped=0

    local installed_commands=()
    if [[ -f "$state_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && installed_commands+=("$line")
        done < "$state_file"
    fi

    read_current_commands
    local current_commands=("${_current_commands[@]+"${_current_commands[@]}"}")
    declare -f "install_${adapter}_command" >/dev/null || current_commands=()

    # Remove commands that were installed but no longer exist in commands/
    for cmd in "${installed_commands[@]+"${installed_commands[@]}"}"; do
        if ! contains "$cmd" "${current_commands[@]+"${current_commands[@]}"}"; then
            echo "    - removing command: $cmd"
            "uninstall_${adapter}_command" "$cmd"
            changed=1
        fi
    done

    # Install or update all current commands
    for cmd in "${current_commands[@]+"${current_commands[@]}"}"; do
        local source_file="$COMMANDS_DIR/${cmd}.md"
        local dest
        dest="$("get_${adapter}_command_dest" "$cmd")"
        if [[ "$adapter" == "codex" ]] && codex_skill_collision "$cmd"; then
            echo "    ! skipped unowned Codex skill: $cmd ($dest)" >&2
            skipped=1
            continue
        fi
        # Rendered for every adapter, as skills are: Cursor, Gemini and Codex install commands
        # too, and a command naming a partial it does not carry is a dangling instruction there.
        # Diffing the rendered text keeps the pass idempotent when only a partial moved on.
        local rendered
        rendered="$(mktemp)"
        craftkit_render_injected "$source_file" "$rendered"
        if [[ ! -f "$dest" ]] || ! diff -q "$rendered" "$dest" &>/dev/null; then
            echo "    + command: $cmd"
            "install_${adapter}_command" "$cmd" "$rendered"
            changed=1
        fi
        rm -f "$rendered"
    done

    [[ $changed -eq 0 && $skipped -eq 0 ]] && echo "    commands: (up to date)"

    printf '%s\n' "${current_commands[@]+"${current_commands[@]}"}" > "$state_file"
}

# `rtk init -g --auto-patch` registers the PreToolUse hook as bare `rtk hook claude`.
# Claude Code spawns hooks under a stripped PATH (/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.)
# with no /opt/homebrew/bin, so a bare name dies with "rtk: command not found". Non-blocking,
# so every Bash call then runs unrewritten and unfiltered. Rewrite to an absolute path after
# each rtk init, the same way _resolve_node_bin pins node for the routing hook.
_rtk_hook_absolutize() {
    local rtk_bin
    rtk_bin="$(command -v rtk 2>/dev/null)" || return 0
    [[ -f "$CLAUDE_SETTINGS" ]] || return 0
    python3 - "$CLAUDE_SETTINGS" "$rtk_bin" << 'PYEOF'
import json, sys
settings_path, rtk_bin = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    settings = json.load(f)
changed = False
for entry in settings.get('hooks', {}).get('PreToolUse', []):
    for h in entry.get('hooks', []):
        cmd = h.get('command', '')
        if 'rtk hook' in cmd and not cmd.startswith('/'):
            h['command'] = cmd.replace('rtk hook', rtk_bin + ' hook', 1)
            changed = True
if changed:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
    print('    rtk hook path (absolute)')
PYEOF
}

ensure_tools() {
    echo ""
    echo "[tools]"

    # RTK: install if missing
    if ! command -v rtk &>/dev/null; then
        echo "    + installing rtk..."
        if command -v brew &>/dev/null; then
            brew install rtk
        else
            curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
        fi
    else
        echo "    rtk $(rtk --version 2>/dev/null | head -1) (ok)"
    fi

    # RTK: wire up the Claude Code auto-rewrite hook (idempotent)
    if command -v rtk &>/dev/null; then
        rtk init -g --auto-patch 2>/dev/null && echo "    rtk hook (ok)" || true
        _rtk_hook_absolutize
    fi

    # Humanizer: de-AI-writing skill (used by /pr-message and /docs). Clone SKILL.md from
    # upstream into ~/.agents/skills, which Codex, Cursor and Gemini read, and symlink it
    # into ~/.claude/skills as a native Agent Skill. No adapter installs it: skills/ has no
    # humanizer, so this is its only install path. The state file records that craftkit put
    # it there, so humanizer=off never removes a copy the user installed.
    hz_src="$HOME/.agents/skills/humanizer"
    # flag: humanizer. off: not installed here, and sync_extras removes it every sync. remove: never, it is a user choice.
    if [[ "$CK_humanizer" == off ]]; then
        :
    elif [[ ! -f "$hz_src/SKILL.md" ]]; then
        echo "    + installing humanizer..."
        hz_tmp="$(mktemp -d)"
        if git clone --depth 1 https://github.com/blader/humanizer.git "$hz_tmp" 2>/dev/null; then
            mkdir -p "$hz_src"
            cp "$hz_tmp/SKILL.md" "$hz_src/SKILL.md"
            mkdir -p "$HOME/.claude/skills"
            ln -sfn "$hz_src" "$HOME/.claude/skills/humanizer"
            echo "$hz_src" > "$STATE_DIR/humanizer-owned"
            echo "    humanizer (ok)"
        else
            echo "    ! humanizer install failed, clone https://github.com/blader/humanizer manually"
        fi
        rm -rf "$hz_tmp"
    else
        echo "    humanizer (ok)"
    fi

}

echo "==> Syncing craftkit..."

# RTK patches shell profile and is interactive, so only run from install.sh,
# never from the post-merge hook.
if [[ "${AGENTIC_SETUP:-0}" == "1" ]]; then
    ensure_tools
fi

# Retiring an adapter deletes its state files but left its staging dir behind: the
# v1.25.1 removal of copilot and crush took the adapters out of ADAPTERS and the
# repo, yet ~/.craftkit/copilot and ~/.craftkit/crush-rules were still on disk
# months later. Staging dirs are ours and are rebuilt every sync, so any whose
# prefix no longer matches a live adapter is an orphan. Pruned by prefix rather
# than by an explicit retired-list, so the next retirement self-cleans.
prune_orphan_staging() {
    local staging="$HOME/.craftkit"
    [[ -d "$staging" ]] || return 0
    local d base live
    for d in "$staging"/*; do
        [[ -d "$d" ]] || continue
        base="$(basename "$d")"
        # bin holds synced scripts; agent-tree is the dashboard's logs, removed by sync_bin when it is off.
        [[ "$base" == "bin" || "$base" == "agent-tree" ]] && continue
        live=0
        for adapter in "${ADAPTERS[@]}"; do
            case "$base" in "$adapter"|"$adapter"-*) live=1; break ;; esac
        done
        if [[ $live -eq 0 ]]; then
            rm -rf "$d"
            echo "    - pruned orphan staging dir: ~/.craftkit/$base"
        fi
    done
}

prune_orphan_staging

# The managed-block marker was named AGENTIC-SKILLS before this repo was called
# craftkit, so the wire format disagreed with the product for six releases and a
# reader had no way to tell whose block it was. Renaming the constant alone would
# make every adapter miss the block already written into the user's file, append a
# second one, and orphan the first, which is exactly the graphify failure mode
# check 21 covers. So the legacy pair is rewritten in place first, before any
# adapter looks for its markers. Idempotent: once rewritten there is nothing left
# to match. The new marker also drops the em-dash, retiring one check 19 exemption.
craftkit_migrate_markers() {
    local f
    for f in "$HOME/.claude/CLAUDE.md" "$HOME/GEMINI.md" "$HOME/.codex/AGENTS.md"; do
        [[ -f "$f" ]] || continue
        grep -qF "BEGIN AGENTIC-SKILLS" "$f" || continue
        python3 - "$f" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
s = s.replace("<!-- BEGIN AGENTIC-SKILLS (managed \u2014 do not edit manually) -->",
              "<!-- BEGIN CRAFTKIT (managed: do not edit manually) -->")
s = s.replace("<!-- END AGENTIC-SKILLS -->", "<!-- END CRAFTKIT -->")
io.open(p, "w", encoding="utf-8").write(s)
PY
        echo "    - migrated legacy managed-block marker in $f"
    done
}

craftkit_migrate_markers

for adapter in "${ADAPTERS[@]}"; do
    echo ""
    echo "[$adapter]"
    sync_rules_adapter "$adapter"
    sync_adapter "$adapter"
    sync_commands_adapter "$adapter"
    if declare -f "install_${adapter}_agent" &>/dev/null; then
        sync_agents_adapter "$adapter"
    fi
    if declare -f "finalize_${adapter}" &>/dev/null; then
        "finalize_${adapter}"
    fi
done

# cross-review.sh and context-source.* are run by synced commands and skills, and an installed
# file cannot know where this repo lives, so the scripts get a fixed path every tool can reach.
# The dashboard viewer and its launcher ride along only while the dashboard is opted into.
sync_bin() {
    local bin="$HOME/.craftkit/bin" link="$HOME/.local/bin/ccdash" name changed=0 names="cross-review.sh context-source.sh context-source.js"
    echo ""
    echo "[bin]"
    mkdir -p "$bin"
    [[ "$CRAFTKIT_DASHBOARD_ON" == 1 ]] && names="$names dashboard.py ccdash"
    for name in $names; do
        cmp -s "$REPO_DIR/scripts/$name" "$bin/$name" && continue
        cp "$REPO_DIR/scripts/$name" "$bin/.$name.tmp" && chmod +x "$bin/.$name.tmp" \
            && mv -f "$bin/.$name.tmp" "$bin/$name" || return 1
        echo "    + $name"
        changed=1
    done
    if [[ "$CRAFTKIT_DASHBOARD_ON" == 1 ]]; then
        if [[ -d "$HOME/.local/bin" && ! -e "$link" && ! -L "$link" ]]; then
            ln -s "$bin/ccdash" "$link" && echo "    + ccdash -> ~/.local/bin" && changed=1
        fi
        if [[ -e "$link" && "$(readlink "$link" 2>/dev/null)" != "$bin/ccdash" ]]; then
            echo "    ! ~/.local/bin/ccdash is not CraftKit's, left as is; remove it to get the synced one"
        else
            case "$(command -v ccdash 2>/dev/null)" in
                "$link"|"$bin/ccdash") ;;
                *) echo "    ! ccdash is not on PATH; add ~/.local/bin (or $bin) to PATH, or run $bin/ccdash" ;;
            esac
        fi
    else
        for name in dashboard.py ccdash; do
            [[ -f "$bin/$name" ]] || continue
            rm -f "$bin/$name" && echo "    - $name" && changed=1
        done
        if [[ "$(readlink "$link" 2>/dev/null)" == "$bin/ccdash" ]]; then
            rm -f "$link" && echo "    - ccdash link" && changed=1
        fi
        # The logs hold tool commands and file paths; off means they go too.
        if [[ -d "$HOME/.craftkit/agent-tree" ]]; then
            rm -rf "$HOME/.craftkit/agent-tree" && echo "    - agent-tree logs" && changed=1
        fi
    fi
    [[ $changed -eq 0 ]] && echo "    bin: (up to date)"
    return 0
}
sync_bin

# Extras a user can turn off or on in the config. Off is enforced on every sync, not only
# under AGENTIC_SETUP, so the choice holds after a git pull.
_pw_note() { echo "    ! playwright: $1; skipped, the rest of the sync continues"; }

# Owned skill names come back from a state file, so each is checked before rm -rf: a plain
# folder name (never . or ..) whose path is a real directory, not a link to elsewhere.
_pw_skill_ok() {
    local re='^[A-Za-z0-9_-][A-Za-z0-9._-]*$'
    [[ $1 =~ $re && -d "$2/$1" && ! -L "$2/$1" ]]
}

sync_playwright() {
    local owned="$STATE_DIR/playwright-owned" failed="$STATE_DIR/playwright-failed" skills="$HOME/.agents/skills"
    local line name before="" added=0 major d
    # flag: playwright. off: nothing installed, and a sync removes what craftkit installed while it was on (the npm package only if craftkit installed it). remove: never, it is a user choice.
    if [[ "$CK_playwright" != on ]]; then
        rm -f "$failed"
        [[ -f "$owned" ]] || return 0
        while IFS= read -r line; do
            name="${line#skill }"
            [[ "$line" == "skill "* ]] && _pw_skill_ok "$name" "$skills" || continue
            rm -rf "${skills:?}/$name" && echo "    - playwright skill: $name"
        done < "$owned"
        if grep -qx package "$owned"; then
            if npm uninstall -g @playwright/cli >/dev/null 2>&1; then
                echo "    - @playwright/cli"
            else
                echo "    ! could not npm uninstall -g @playwright/cli; the next sync will retry"
                return 0
            fi
        fi
        rm -f "$owned"
        return 0
    fi
    # A failed install needs the network, so unattended syncs leave it to an explicit retry.
    if [[ -f "$failed" && "${AGENTIC_SETUP:-0}" != 1 && "${_ck_configure:-0}" != 1 ]]; then
        _pw_note "the last install failed ($(cat "$failed")); bash sync.sh --configure retries it"
        return 0
    fi
    rm -f "$failed"
    command -v npm >/dev/null 2>&1 || { _pw_note "npm not found"; return 0; }
    major="$(node -v 2>/dev/null | sed 's/^v//;s/\..*//')"
    [[ "$major" =~ ^[0-9]+$ && "$major" -ge 20 ]] || { _pw_note "Node 20+ required (found ${major:-none})"; return 0; }
    if ! command -v playwright-cli >/dev/null 2>&1; then
        if ! npm install -g @playwright/cli@latest >/dev/null 2>&1; then
            echo "npm install" > "$failed"
            _pw_note "npm install -g @playwright/cli failed (network?)"; return 0
        fi
        hash -r
        echo package >> "$owned"
        echo "    + @playwright/cli"
    fi
    if [[ -f "$owned" ]] && grep -qx skills "$owned"; then
        added=1
        while IFS= read -r line; do
            if [[ "$line" == "skill "* && ! -d "$skills/${line#skill }" ]]; then added=0; fi
        done < "$owned"
        [[ $added -eq 1 ]] && return 0
    fi
    # Which skill folders the CLI writes is its business, so ownership is the set it added.
    for d in "$skills"/*/; do
        if [[ -d "$d" ]]; then before="$before$(basename "$d")"$'\n'; fi
    done
    if ! playwright-cli install --skills=agents -g >/dev/null 2>&1; then
        echo "skill install" > "$failed"
        _pw_note "playwright-cli install --skills=agents -g failed"; return 0
    fi
    added=0
    for d in "$skills"/*/; do
        name="$(basename "$d")"
        [[ -d "$d" ]] && _pw_skill_ok "$name" "$skills" || continue
        printf '%s' "$before" | grep -qxF -- "$name" && continue
        grep -qxF "skill $name" "$owned" 2>/dev/null || echo "skill $name" >> "$owned"
        echo "    + playwright skill: $name"
        added=1
    done
    if [[ $added -eq 0 ]] && ! grep -qx skills "$owned" 2>/dev/null; then
        echo "no skill folder in ~/.agents/skills" > "$failed"
        _pw_note "playwright-cli added no skill folder under ~/.agents/skills, so craftkit owns none"
        return 0
    fi
    grep -qx skills "$owned" 2>/dev/null || echo skills >> "$owned"
}

sync_extras() {
    local out hz_dir="$HOME/.agents/skills/humanizer" hz_link="$HOME/.claude/skills/humanizer" hz_owned="$STATE_DIR/humanizer-owned"
    echo ""
    echo "[extras]"
    out="$(
        # Only what ensure_tools recorded installing goes; a humanizer the user installed stays.
        if [[ "$CK_humanizer" == off && -f "$hz_owned" ]]; then
            if [[ -L "$hz_link" && "$(readlink "$hz_link")" == "$hz_dir" ]]; then
                rm -f "$hz_link" && echo "    - humanizer link"
            fi
            if [[ -d "$hz_dir" && ! -L "$hz_dir" ]]; then
                rm -rf "$hz_dir" && echo "    - humanizer"
            fi
            rm -f "$hz_owned"
        fi
        sync_playwright
    )"
    if [[ -n "$out" ]]; then printf '%s\n' "$out"; else echo "    extras: (up to date)"; fi
}
sync_extras

echo ""
[[ -n "$_ck_repo_version" ]] && printf '%s\n' "$_ck_repo_version" > "$_ck_version_file"

echo "Sync complete."
