#!/usr/bin/env bash
# init-copilot-agents.sh — wires agentic-skills into a project's Copilot Chat
#
# Generates:
#   .github/copilot-instructions.md  — always-active rules (auto-loaded every chat)
#   .github/agents/<skill>.agent.md  — @-invokable agents per skill/command
#
# Usage:
#   bash ~/agentic-skills/scripts/init-copilot-agents.sh           # current dir
#   bash ~/agentic-skills/scripts/init-copilot-agents.sh /path/to/project

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES_DIR="$REPO_DIR/rules"
SKILLS_DIR="$REPO_DIR/skills"
COMMANDS_DIR="$REPO_DIR/commands"

TARGET_DIR="${1:-$(pwd)}"
AGENTS_DIR="$TARGET_DIR/.github/agents"
COPILOT_INSTRUCTIONS="$TARGET_DIR/.github/copilot-instructions.md"

mkdir -p "$AGENTS_DIR"

# ── copilot-instructions.md ───────────────────────────────────────────────────
# Concat all rules — Copilot auto-loads this every chat session in this repo.

echo "→ .github/copilot-instructions.md"
{
    echo "<!-- managed by agentic-skills — re-run init-copilot-agents.sh to update -->"
    for f in "$RULES_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        echo ""
        # Strip frontmatter (--- ... ---) — not needed in instructions file
        awk '/^---$/{if(fm==0){fm=1;next}else{fm=0;next}} fm==0{print}' "$f"
        echo ""
    done
} > "$COPILOT_INSTRUCTIONS"
echo "   written"

# ── .github/agents/<name>.agent.md ───────────────────────────────────────────
# One agent file per skill and command. Invoked with @<name> in Copilot Chat.

echo "→ .github/agents/"

_write_agent() {
    local name="$1"
    local source_file="$2"
    local dest="$AGENTS_DIR/${name}.agent.md"

    # Strip alwaysApply line — not meaningful for Copilot agents
    sed '/^alwaysApply:/d' "$source_file" > "$dest"
    echo "   + @${name}"
}

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

echo ""
echo "Done. Invoke in Copilot Chat:"
echo "  @fe-test     write tests for this component"
echo "  @fe-review   review for EVPMR violations"
echo "  @fe-scaffold scaffold a new feature module"
echo "  @debug       help me debug this"
echo ""
echo "Commit .github/ to share with your team."
