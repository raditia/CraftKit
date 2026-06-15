#!/usr/bin/env bash
# init-copilot-agents.sh — wires craftkit into a project's Copilot Chat
#
# Generates:
#   .github/copilot-instructions.md  — always-active rules (auto-loaded every chat)
#   .github/agents/<skill>.agent.md  — @-invokable agents per skill/command
#
# Registers the project path in ~/.craftkit-state/copilot-projects so
# sync.sh can auto-update agents on every git pull.
#
# Usage:
#   bash ~/craftkit/scripts/init-copilot-agents.sh           # current dir
#   bash ~/craftkit/scripts/init-copilot-agents.sh /path/to/project

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$REPO_DIR/rules"
SKILLS_DIR="$REPO_DIR/skills"
COMMANDS_DIR="$REPO_DIR/commands"
STATE_DIR="$HOME/.craftkit-state"
PROJECTS_FILE="$STATE_DIR/copilot-projects"

TARGET_DIR="${1:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"  # normalize to absolute path
AGENTS_DIR="$TARGET_DIR/.github/agents"
COPILOT_INSTRUCTIONS="$TARGET_DIR/.github/copilot-instructions.md"

mkdir -p "$AGENTS_DIR" "$STATE_DIR"

# ── copilot-instructions.md ───────────────────────────────────────────────────

echo "→ .github/copilot-instructions.md"
{
    echo "<!-- managed by craftkit — do not edit manually -->"
    for f in "$RULES_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        echo ""
        awk '/^---$/{if(fm==0){fm=1;next}else{fm=0;next}} fm==0{print}' "$f"
        echo ""
    done
} > "$COPILOT_INSTRUCTIONS"
echo "   written"

# ── .github/agents/<name>.agent.md ───────────────────────────────────────────

echo "→ .github/agents/"

_write_agent() {
    local name="$1"
    local source_file="$2"
    local dest="$AGENTS_DIR/${name}.agent.md"
    sed '/^alwaysApply:/d' "$source_file" > "$dest"
    echo "   + @${name}"
}

# Remove stale agents (skill/command deleted from repo)
for existing in "$AGENTS_DIR"/*.agent.md; do
    [[ -f "$existing" ]] || continue
    agent_name="$(basename "$existing" .agent.md)"
    skill_exists=0
    [[ -f "$SKILLS_DIR/$agent_name/SKILL.md" ]] && skill_exists=1
    [[ -f "$COMMANDS_DIR/$agent_name.md" ]]     && skill_exists=1
    if [[ $skill_exists -eq 0 ]]; then
        rm "$existing"
        echo "   - removed @${agent_name}"
    fi
done

# Install/update agents
for dir in "$SKILLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    skill_name="$(basename "$dir")"
    source_file="$dir/SKILL.md"
    [[ -f "$source_file" ]] || continue
    _write_agent "$skill_name" "$source_file"
done

for f in "$COMMANDS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    cmd_name="$(basename "$f" .md)"
    _write_agent "$cmd_name" "$f"
done

# ── Register project for auto-sync ───────────────────────────────────────────

if [[ ! -f "$PROJECTS_FILE" ]] || ! grep -qF "$TARGET_DIR" "$PROJECTS_FILE" 2>/dev/null; then
    echo "$TARGET_DIR" >> "$PROJECTS_FILE"
    echo ""
    echo "   registered for auto-sync on git pull"
fi

echo ""
echo "Done. Invoke in Copilot Chat:"
echo "  @fe-test     write tests for this component"
echo "  @fe-review   review for EVPMR violations"
echo "  @fe-scaffold scaffold a new feature module"
echo "  @debug       help me debug this"
echo ""
echo "Commit .github/ to share with your team."
