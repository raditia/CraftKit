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
