#!/usr/bin/env bash
# Cursor: installs skills as user-level rules in ~/.cursor/rules/

CURSOR_RULES_DIR="$HOME/.cursor/rules"

get_cursor_dest() {
    local skill_name="$1"
    echo "$CURSOR_RULES_DIR/${skill_name}.mdc"
}

install_cursor_skill() {
    local skill_name="$1"
    local source_file="$2"
    mkdir -p "$CURSOR_RULES_DIR"
    cp "$source_file" "$CURSOR_RULES_DIR/${skill_name}.mdc"
}

uninstall_cursor_skill() {
    local skill_name="$1"
    rm -f "$CURSOR_RULES_DIR/${skill_name}.mdc"
}

get_cursor_rule_dest() { echo "$CURSOR_RULES_DIR/${1}.mdc"; }

# Rules are always-apply; inject alwaysApply: true after the opening ---
# Cursor is the one tool with NATIVE path scoping, so a `platform:` rule becomes a
# glob-scoped rule rather than an always-on one: Cursor loads it only when the open file
# matches. Claude Code has no user-scope equivalent and uses a SessionStart hook instead.
# One row per platform that actually has a scoped rule. A scoped rule with no row here
# falls back to alwaysApply, so check.sh 23b fails rather than letting it go always-on.
_CURSOR_PLATFORM_GLOBS_fe="**/*.ts,**/*.tsx,**/*.js,**/*.jsx"

_cursor_rule_globs() {
    local plat k globs all="" keys
    plat="$(awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^platform:/{sub(/^platform:[[:space:]]*/,"");print;exit}' "$1")"
    [[ -z "$plat" ]] && return 1
    local IFS=', '
    read -ra keys <<< "$plat"
    for k in "${keys[@]}"; do
        case "$k" in
            fe) globs=$_CURSOR_PLATFORM_GLOBS_fe ;;
            *)  globs="" ;;
        esac
        [[ -n "$globs" ]] && all="${all:+$all,}$globs"
    done
    [[ -z "$all" ]] && return 1
    echo "$all"
}

_cursor_render_rule() {
    local globs
    if globs="$(_cursor_rule_globs "$1")"; then
        awk -v g="$globs" 'NR==1 && /^---$/{print; print "alwaysApply: false"; print "globs: " g; next} {print}' "$1" > "$2"
    else
        awk 'NR==1 && /^---$/{print; print "alwaysApply: true"; next} {print}' "$1" > "$2"
    fi
}

install_cursor_rule() {
    local name="$1"
    local source_file="$2"
    mkdir -p "$CURSOR_RULES_DIR"
    _cursor_render_rule "$source_file" "$CURSOR_RULES_DIR/${name}.mdc"
}

# Currency hook used by sync.sh's rules loop: renders to a temp file so the diff-skip
# check compares dest against the *rendered* output, not the raw source, because otherwise the
# injected alwaysApply line makes every rule look changed on every run. sync.sh removes
# the returned temp file after diffing.
effective_cursor_rule_source() {
    local source_file="$2"
    local tmp
    tmp="$(mktemp)"
    _cursor_render_rule "$source_file" "$tmp"
    echo "$tmp"
}

uninstall_cursor_rule() { rm -f "$CURSOR_RULES_DIR/${1}.mdc"; }

get_cursor_command_dest() { get_cursor_dest "$1"; }
install_cursor_command()   { install_cursor_skill "$@"; }
uninstall_cursor_command() { uninstall_cursor_skill "$@"; }
