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

mkdir -p "$STATE_DIR"

source "$REPO_DIR/adapters/claude.sh"
source "$REPO_DIR/adapters/cursor.sh"
source "$REPO_DIR/adapters/copilot.sh"
source "$REPO_DIR/adapters/gemini.sh"
source "$REPO_DIR/adapters/codex.sh"
source "$REPO_DIR/adapters/crush.sh"

ADAPTERS=("claude" "cursor" "copilot" "gemini" "codex" "crush")

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
        local source_file="$RULES_DIR/${rule}.md"
        local dest
        dest="$("get_${adapter}_rule_dest" "$rule")"
        if [[ ! -f "$dest" ]] || ! diff -q "$source_file" "$dest" &>/dev/null; then
            echo "    + rule: $rule"
            "install_${adapter}_rule" "$rule" "$source_file"
            changed=1
        fi
    done

    [[ $changed -eq 0 ]] && echo "    rules: (up to date)"

    printf '%s\n' "${current_rules[@]+"${current_rules[@]}"}" > "$state_file"
}

sync_agents_adapter() {
    local adapter="$1"
    local state_file="$STATE_DIR/${adapter}-agents"
    local changed=0

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
        local dest
        dest="$("get_${adapter}_agent_dest" "$agent")"
        if [[ ! -f "$dest" ]] || ! diff -q "$source_file" "$dest" &>/dev/null; then
            echo "    + agent: $agent"
            "install_${adapter}_agent" "$agent" "$source_file"
            changed=1
        fi
    done

    [[ $changed -eq 0 ]] && echo "    agents: (up to date)"

    printf '%s\n' "${current_agents[@]+"${current_agents[@]}"}" > "$state_file"
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

}

echo "==> Syncing craftkit..."

# RTK patches shell profile and is interactive — only run from install.sh,
# never from the post-merge hook.
if [[ "${AGENTIC_SETUP:-0}" == "1" ]]; then
    ensure_tools
fi

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
sync_copilot_projects() {
    local projects_file="$STATE_DIR/copilot-projects"
    [[ -f "$projects_file" ]] || return 0

    local updated=0
    local stale=()

    while IFS= read -r project_dir; do
        [[ -n "$project_dir" ]] || continue
        if [[ ! -d "$project_dir/.github/agents" ]]; then
            stale+=("$project_dir")
            continue
        fi
        echo ""
        echo "[copilot-agents] $project_dir"
        bash "$REPO_DIR/scripts/init-copilot-agents.sh" "$project_dir" 2>&1 | sed 's/^/    /'
        updated=1
    done < "$projects_file"

    # Remove stale entries (project deleted or agents dir removed)
    if [[ ${#stale[@]} -gt 0 ]]; then
        for s in "${stale[@]}"; do
            grep -vF "$s" "$projects_file" > "${projects_file}.tmp" && mv "${projects_file}.tmp" "$projects_file" || true
            echo "    [copilot-agents] unregistered: $s (agents dir gone)"
        done
    fi
}

sync_copilot_projects

echo ""
echo "Sync complete."
