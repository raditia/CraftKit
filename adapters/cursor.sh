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

install_cursor_rule() {
    local name="$1"
    local source_file="$2"
    local dest="$CURSOR_RULES_DIR/${name}.mdc"
    mkdir -p "$CURSOR_RULES_DIR"
    # Rules are always-apply; inject alwaysApply: true after the opening ---
    awk 'NR==1 && /^---$/{print; print "alwaysApply: true"; next} {print}' "$source_file" > "$dest"
}

uninstall_cursor_rule() { rm -f "$CURSOR_RULES_DIR/${1}.mdc"; }

get_cursor_command_dest() { get_cursor_dest "$1"; }
install_cursor_command()   { install_cursor_skill "$@"; }
uninstall_cursor_command() { uninstall_cursor_skill "$@"; }
