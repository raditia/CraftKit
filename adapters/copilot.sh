#!/usr/bin/env bash
# GitHub Copilot: copies skill files to ~/.agentic-skills/copilot/ and registers
# them as file-based custom instructions in VS Code's settings.json.
#
# alwaysApply: true  → registered in codeGeneration.instructions AND reviewSelection.instructions
#                      (covers inline gen + Copilot Chat code and review requests)
# alwaysApply: false → registered in codeGeneration.instructions only
#                      (available as context when user invokes by name / natural language)

COPILOT_SKILLS_DIR="$HOME/.agentic-skills/copilot"

_vscode_settings_path() {
    case "$(uname -s)" in
        Darwin) echo "$HOME/Library/Application Support/Code/User/settings.json" ;;
        Linux)  echo "$HOME/.config/Code/User/settings.json" ;;
        *)      echo "" ;;
    esac
}

_CODEGEN_KEY="github.copilot.chat.codeGeneration.instructions"
_REVIEW_KEY="github.copilot.chat.reviewSelection.instructions"

_copilot_is_always_apply() {
    local skill_name="$1"
    local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
    grep -q "^alwaysApply: true" "$skill_file" 2>/dev/null
}

# VS Code settings.json is JSONC — may have trailing commas that jq rejects.
# Strip trailing commas before any jq operation.
_normalize_jsonc() {
    python3 -c "
import re, sys
text = open(sys.argv[1]).read()
text = re.sub(r',(\s*[}\]])', r'\1', text)
sys.stdout.write(text)
" "$1"
}

_register_copilot_file() {
    local skill_path="$1"
    local key="$2"
    local settings
    settings="$(_vscode_settings_path)"
    [[ -z "$settings" || ! -f "$settings" ]] && return 0

    if ! command -v jq &>/dev/null; then
        echo "    [copilot] jq not found — file copied but VS Code settings not updated"
        echo "    Add manually: { \"file\": \"$skill_path\" } to $key"
        return 0
    fi

    local tmp
    tmp="$(mktemp)"
    _normalize_jsonc "$settings" | jq --arg path "$skill_path" --arg key "$key" '
        .[$key] //= [] |
        .[$key] |= (map(select(.file != $path)) + [{"file": $path}])
    ' > "$tmp" && mv "$tmp" "$settings"
}

_unregister_copilot_file() {
    local skill_path="$1"
    local key="$2"
    local settings
    settings="$(_vscode_settings_path)"
    [[ -z "$settings" || ! -f "$settings" ]] && return 0
    command -v jq &>/dev/null || return 0

    local tmp
    tmp="$(mktemp)"
    _normalize_jsonc "$settings" | jq --arg path "$skill_path" --arg key "$key" '
        .[$key] //= [] |
        .[$key] |= map(select(.file != $path))
    ' > "$tmp" && mv "$tmp" "$settings"
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
    _register_copilot_file "$dest" "$_CODEGEN_KEY"
    if _copilot_is_always_apply "$skill_name"; then
        _register_copilot_file "$dest" "$_REVIEW_KEY"
    fi
}

uninstall_copilot_skill() {
    local skill_name="$1"
    local dest="$COPILOT_SKILLS_DIR/${skill_name}.md"
    _unregister_copilot_file "$dest" "$_CODEGEN_KEY"
    _unregister_copilot_file "$dest" "$_REVIEW_KEY"
    rm -f "$dest"
}

get_copilot_rule_dest() {
    echo "$COPILOT_SKILLS_DIR/${1}.md"
}

install_copilot_rule() {
    local name="$1"
    local source_file="$2"
    local dest="$COPILOT_SKILLS_DIR/${name}.md"
    mkdir -p "$COPILOT_SKILLS_DIR"
    cp "$source_file" "$dest"
    _register_copilot_file "$dest" "$_CODEGEN_KEY"
    _register_copilot_file "$dest" "$_REVIEW_KEY"
}

uninstall_copilot_rule() {
    local dest="$COPILOT_SKILLS_DIR/${1}.md"
    _unregister_copilot_file "$dest" "$_CODEGEN_KEY"
    _unregister_copilot_file "$dest" "$_REVIEW_KEY"
    rm -f "$dest"
}

get_copilot_command_dest() {
    echo "$COPILOT_SKILLS_DIR/${1}.md"
}

install_copilot_command() {
    local name="$1"
    local source_file="$2"
    local dest="$COPILOT_SKILLS_DIR/${name}.md"
    mkdir -p "$COPILOT_SKILLS_DIR"
    cp "$source_file" "$dest"
    _register_copilot_file "$dest" "$_CODEGEN_KEY"
}

uninstall_copilot_command() {
    local dest="$COPILOT_SKILLS_DIR/${1}.md"
    _unregister_copilot_file "$dest" "$_CODEGEN_KEY"
    rm -f "$dest"
}
