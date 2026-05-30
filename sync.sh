#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: bash 4+ required. On macOS: brew install bash"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$HOME/.agentic-skills-state"
SKILLS_DIR="$REPO_DIR/skills"

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

# Collects skill names that have a file for the given adapter into _current_skills
read_current_skills() {
    local adapter="$1"
    _current_skills=()
    if [[ ! -d "$SKILLS_DIR" ]]; then return; fi
    for skill_dir in "$SKILLS_DIR"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        if [[ -f "$skill_dir/${adapter}.md" ]]; then
            _current_skills+=("$skill_name")
        fi
    done
}

sync_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/$adapter"
    local changed=0

    read_state "$adapter"
    local installed_skills=("${_state_skills[@]+"${_state_skills[@]}"}")

    read_current_skills "$adapter"
    local current_skills=("${_current_skills[@]+"${_current_skills[@]}"}")

    # Remove skills that were installed but are no longer in the repo
    for skill in "${installed_skills[@]+"${installed_skills[@]}"}"; do
        if ! contains "$skill" "${current_skills[@]+"${current_skills[@]}"}"; then
            echo "    - removing: $skill"
            "uninstall_${adapter}_skill" "$skill"
            changed=1
        fi
    done

    # Install or update all current skills
    for skill in "${current_skills[@]+"${current_skills[@]}"}"; do
        local source_file="$SKILLS_DIR/$skill/${adapter}.md"
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

echo "==> Syncing agentic-skills..."
for adapter in "${ADAPTERS[@]}"; do
    echo ""
    echo "[$adapter]"
    sync_adapter "$adapter"
done
echo ""
echo "Sync complete."
