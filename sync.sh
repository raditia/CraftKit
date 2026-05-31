#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: bash 4+ required. On macOS: brew install bash"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.agentic-skills-state"
SKILLS_DIR="$REPO_DIR/skills"
COMMANDS_DIR="$REPO_DIR/commands"

mkdir -p "$STATE_DIR"

source "$REPO_DIR/adapters/claude.sh"
source "$REPO_DIR/adapters/cursor.sh"
source "$REPO_DIR/adapters/copilot.sh"
source "$REPO_DIR/adapters/gemini.sh"

ADAPTERS=("claude" "cursor" "copilot" "gemini")

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
            [[ -n "$line" ]] && _state_skills+=("$line")
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

# Collects command names from commands/*.md
read_current_commands() {
    _current_commands=()
    if [[ ! -d "$COMMANDS_DIR" ]]; then return; fi
    for f in "$COMMANDS_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        _current_commands+=("$(basename "$f" .md)")
    done
}

sync_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/$adapter"
    local changed=0

    read_state "$adapter"
    local installed_skills=("${_state_skills[@]+"${_state_skills[@]}"}")

    read_current_skills
    local current_skills=("${_current_skills[@]+"${_current_skills[@]}"}")

    # Remove skills that were installed but are no longer in the repo
    for skill in "${installed_skills[@]+"${installed_skills[@]}"}"; do
        if ! contains "$skill" "${current_skills[@]+"${current_skills[@]}"}"; then
            echo "    - removing: $skill"
            "uninstall_${adapter}_skill" "$skill"
            changed=1
        fi
    done

    # Install or update all current skills (all adapters share SKILL.md)
    for skill in "${current_skills[@]+"${current_skills[@]}"}"; do
        local source_file="$SKILLS_DIR/$skill/SKILL.md"
        local dest
        dest="$("get_${adapter}_dest" "$skill")"

        if [[ ! -f "$dest" ]] || ! diff -q "$source_file" "$dest" &>/dev/null; then
            echo "    + installing: $skill"
            "install_${adapter}_skill" "$skill" "$source_file"
            changed=1
        fi
    done

    if [[ $changed -eq 0 ]]; then
        echo "    (up to date)"
    fi

    # Persist new state
    printf '%s\n' "${current_skills[@]+"${current_skills[@]}"}" > "$state_file"
}

sync_commands_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/${adapter}-commands"
    local changed=0

    local installed_commands=()
    if [[ -f "$state_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && installed_commands+=("$line")
        done < "$state_file"
    fi

    read_current_commands
    local current_commands=("${_current_commands[@]+"${_current_commands[@]}"}")

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
        if [[ ! -f "$dest" ]] || ! diff -q "$source_file" "$dest" &>/dev/null; then
            echo "    + command: $cmd"
            "install_${adapter}_command" "$cmd" "$source_file"
            changed=1
        fi
    done

    [[ $changed -eq 0 ]] && echo "    commands: (up to date)"

    printf '%s\n' "${current_commands[@]+"${current_commands[@]}"}" > "$state_file"
}

ensure_tools() {
    echo ""
    echo "[tools]"

    # RTK — install if missing
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

    # RTK — wire up the Claude Code auto-rewrite hook (idempotent)
    if command -v rtk &>/dev/null; then
        rtk init -g --auto-patch 2>/dev/null && echo "    rtk hook (ok)" || true
    fi

    # Caveman — install if the skill file is missing
    if [[ ! -f "$HOME/.claude/commands/caveman.md" ]]; then
        echo "    + installing caveman..."
        curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/main/install.sh | bash
    else
        echo "    caveman (ok)"
    fi
}

echo "==> Syncing agentic-skills..."
ensure_tools
for adapter in "${ADAPTERS[@]}"; do
    echo ""
    echo "[$adapter]"
    sync_adapter "$adapter"
    sync_commands_adapter "$adapter"
    if declare -f "finalize_${adapter}" &>/dev/null; then
        "finalize_${adapter}"
    fi
done
echo ""
echo "Sync complete."
