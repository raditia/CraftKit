#!/usr/bin/env bash
# GitHub Copilot: copies skill files to ~/.agentic-skills/copilot/ and registers
# them as file-based custom instructions in VS Code's settings.json.

COPILOT_SKILLS_DIR="$HOME/.agentic-skills/copilot"

_vscode_settings_path() {
    case "$(uname -s)" in
        Darwin) echo "$HOME/Library/Application Support/Code/User/settings.json" ;;
        Linux)  echo "$HOME/.config/Code/User/settings.json" ;;
        *)      echo "" ;;
    esac
}

_copilot_settings_key="github.copilot.chat.codeGeneration.instructions"

_register_copilot_file() {
    local skill_path="$1"
    local settings
    settings="$(_vscode_settings_path)"
    [[ -z "$settings" || ! -f "$settings" ]] && return 0

    if ! command -v jq &>/dev/null; then
        echo "    [copilot] jq not found — file copied but VS Code settings not updated"
        echo "    Add manually: { \"file\": \"$skill_path\" } to $_copilot_settings_key"
        return 0
    fi

    local tmp
    tmp="$(mktemp)"
    jq --arg path "$skill_path" --arg key "$_copilot_settings_key" '
        .[$key] //= [] |
        .[$key] |= (map(select(.file != $path)) + [{"file": $path}])
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
}

_unregister_copilot_file() {
    local skill_path="$1"
    local settings
    settings="$(_vscode_settings_path)"
    [[ -z "$settings" || ! -f "$settings" ]] && return 0
    command -v jq &>/dev/null || return 0

    local tmp
    tmp="$(mktemp)"
    jq --arg path "$skill_path" --arg key "$_copilot_settings_key" '
        .[$key] //= [] |
        .[$key] |= map(select(.file != $path))
    ' "$settings" > "$tmp" && mv "$tmp" "$settings"
}

get_copilot_dest() {
    local skill_name="$1"
    echo "$COPILOT_SKILLS_DIR/${skill_name}.md"
}

install_copilot_skill() {
    local skill_name="$1"
    local source_file="$2"
    local dest="$COPILOT_SKILLS_DIR/${skill_name}.md"
    mkdir -p "$COPILOT_SKILLS_DIR"
    cp "$source_file" "$dest"
    _register_copilot_file "$dest"
}

uninstall_copilot_skill() {
    local skill_name="$1"
    local dest="$COPILOT_SKILLS_DIR/${skill_name}.md"
    _unregister_copilot_file "$dest"
    rm -f "$dest"
}
