#!/usr/bin/env bash
# Claude Code: installs skills as slash commands in ~/.claude/commands/

CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"

get_claude_dest() {
    local skill_name="$1"
    echo "$CLAUDE_COMMANDS_DIR/${skill_name}.md"
}

install_claude_skill() {
    local skill_name="$1"
    local source_file="$2"
    mkdir -p "$CLAUDE_COMMANDS_DIR"
    cp "$source_file" "$CLAUDE_COMMANDS_DIR/${skill_name}.md"
}

uninstall_claude_skill() {
    local skill_name="$1"
    rm -f "$CLAUDE_COMMANDS_DIR/${skill_name}.md"
}
