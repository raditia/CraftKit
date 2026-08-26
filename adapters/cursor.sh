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
_cursor_render_rule() {
    awk 'NR==1 && /^---$/{print; print "alwaysApply: true"; next} {print}' "$1" > "$2"
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
