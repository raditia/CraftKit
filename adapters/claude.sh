#!/usr/bin/env bash
# Claude Code adapter.
#
# alwaysApply: true  → written into ~/.claude/CLAUDE.md (auto-loaded every session)
# alwaysApply: false → installed as ~/.claude/commands/<skill>.md (slash command)

CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
CLAUDE_RULES_DIR="$HOME/.craftkit/claude-rules"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
_CLAUDE_SECTION_START="<!-- BEGIN AGENTIC-SKILLS (managed — do not edit manually) -->"
_CLAUDE_SECTION_END="<!-- END AGENTIC-SKILLS -->"

# Returns 0 if the skill's SKILL.md has alwaysApply: true
_claude_is_rule() {
    local skill_name="$1"
    local skill_file="$SKILLS_DIR/$skill_name/SKILL.md"
    grep -q "^alwaysApply: true" "$skill_file" 2>/dev/null
}

# Rebuilds the managed section in ~/.claude/CLAUDE.md from all staged rule files
_rebuild_claude_md() {
    local tmp_section
    tmp_section="$(mktemp)"

    {
        echo "$_CLAUDE_SECTION_START"
        for f in "$CLAUDE_RULES_DIR"/*.md; do
            [[ -f "$f" ]] || continue
            echo ""
            cat "$f"
            echo ""
        done
        echo "$_CLAUDE_SECTION_END"
    } > "$tmp_section"

    mkdir -p "$(dirname "$CLAUDE_MD")"

    if [[ ! -f "$CLAUDE_MD" ]]; then
        cp "$tmp_section" "$CLAUDE_MD"
        rm "$tmp_section"
        return
    fi

    if grep -qF "$_CLAUDE_SECTION_START" "$CLAUDE_MD"; then
        python3 - "$CLAUDE_MD" "$tmp_section" << 'PYEOF'
import re, sys
md_path, section_path = sys.argv[1], sys.argv[2]
with open(md_path) as f:
    content = f.read()
with open(section_path) as f:
    replacement = f.read().strip()
new_content = re.sub(
    r'<!-- BEGIN AGENTIC-SKILLS.*?<!-- END AGENTIC-SKILLS -->',
    replacement,
    content,
    flags=re.DOTALL,
)
with open(md_path, 'w') as f:
    f.write(new_content)
PYEOF
    else
        { echo ""; cat "$tmp_section"; } >> "$CLAUDE_MD"
    fi

    rm "$tmp_section"
}

# Removes the managed section from ~/.claude/CLAUDE.md when no rule skills remain
_remove_claude_md_section() {
    [[ ! -f "$CLAUDE_MD" ]] && return
    grep -qF "$_CLAUDE_SECTION_START" "$CLAUDE_MD" || return

    python3 - "$CLAUDE_MD" << 'PYEOF'
import re, sys
md_path = sys.argv[1]
with open(md_path) as f:
    content = f.read()
new_content = re.sub(
    r'\n?<!-- BEGIN AGENTIC-SKILLS.*?<!-- END AGENTIC-SKILLS -->\n?',
    '',
    content,
    flags=re.DOTALL,
)
with open(md_path, 'w') as f:
    f.write(new_content)
PYEOF
}

get_claude_rule_dest() {
    echo "$CLAUDE_RULES_DIR/${1}.md"
}

install_claude_rule() {
    local name="$1"
    local source_file="$2"
    mkdir -p "$CLAUDE_RULES_DIR"
    cp "$source_file" "$CLAUDE_RULES_DIR/${name}.md"
    _rebuild_claude_md
    rm -f "$CLAUDE_COMMANDS_DIR/${name}.md"
}

uninstall_claude_rule() {
    local name="$1"
    rm -f "$CLAUDE_RULES_DIR/${name}.md"
    if compgen -G "$CLAUDE_RULES_DIR/*.md" &>/dev/null; then
        _rebuild_claude_md
    else
        _remove_claude_md_section
    fi
}

get_claude_command_dest() {
    echo "$CLAUDE_COMMANDS_DIR/${1}.md"
}

install_claude_command() {
    local name="$1"
    local source_file="$2"
    mkdir -p "$CLAUDE_COMMANDS_DIR"
    cp "$source_file" "$CLAUDE_COMMANDS_DIR/${name}.md"
}

uninstall_claude_command() {
    rm -f "$CLAUDE_COMMANDS_DIR/${1}.md"
}

get_claude_dest() {
    local skill_name="$1"
    if _claude_is_rule "$skill_name"; then
        echo "$CLAUDE_RULES_DIR/${skill_name}.md"
    else
        echo "$CLAUDE_COMMANDS_DIR/${skill_name}.md"
    fi
}

install_claude_skill() {
    local skill_name="$1"
    local source_file="$2"
    if _claude_is_rule "$skill_name"; then
        mkdir -p "$CLAUDE_RULES_DIR"
        cp "$source_file" "$CLAUDE_RULES_DIR/${skill_name}.md"
        _rebuild_claude_md
        # Remove old slash command if this skill was previously a command
        rm -f "$CLAUDE_COMMANDS_DIR/${skill_name}.md"
    else
        mkdir -p "$CLAUDE_COMMANDS_DIR"
        cp "$source_file" "$CLAUDE_COMMANDS_DIR/${skill_name}.md"
        # Remove old rule entry if this skill was previously a rule
        if [[ -f "$CLAUDE_RULES_DIR/${skill_name}.md" ]]; then
            rm -f "$CLAUDE_RULES_DIR/${skill_name}.md"
            if compgen -G "$CLAUDE_RULES_DIR/*.md" &>/dev/null; then
                _rebuild_claude_md
            else
                _remove_claude_md_section
            fi
        fi
    fi
}

# Called after every sync pass — rebuilds CLAUDE.md if the managed section is
# missing or stale (e.g. file was manually edited or accidentally deleted).
finalize_claude() {
    local has_rules=0
    if compgen -G "$CLAUDE_RULES_DIR/*.md" &>/dev/null; then
        has_rules=1
    fi

    if [[ $has_rules -eq 1 ]]; then
        if [[ ! -f "$CLAUDE_MD" ]] || ! grep -qF "$_CLAUDE_SECTION_START" "$CLAUDE_MD"; then
            echo "    ! CLAUDE.md managed section missing — rebuilding"
            _rebuild_claude_md
        fi
    else
        if [[ -f "$CLAUDE_MD" ]] && grep -qF "$_CLAUDE_SECTION_START" "$CLAUDE_MD"; then
            echo "    ! CLAUDE.md has stale managed section (no rule skills) — cleaning"
            _remove_claude_md_section
        fi
    fi
}

uninstall_claude_skill() {
    local skill_name="$1"
    local rule_file="$CLAUDE_RULES_DIR/${skill_name}.md"
    local cmd_file="$CLAUDE_COMMANDS_DIR/${skill_name}.md"

    if [[ -f "$rule_file" ]]; then
        rm -f "$rule_file"
        if compgen -G "$CLAUDE_RULES_DIR/*.md" &>/dev/null; then
            _rebuild_claude_md
        else
            _remove_claude_md_section
        fi
    fi

    rm -f "$cmd_file"
}
