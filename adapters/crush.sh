#!/usr/bin/env bash
# Crush adapter (formerly OpenCode, now charmbracelet/crush).
#
# Rules → managed block in ~/.config/crush/CRUSH.md (auto-loaded globally)
# Skills + Commands → individual .md files in ~/.config/crush/skills/
#   (each file becomes an invokable command by filename)

CRUSH_SKILLS_DIR="$HOME/.config/crush/skills"
CRUSH_RULES_STAGING="$HOME/.craftkit/crush-rules"
CRUSH_MD="$HOME/.config/crush/CRUSH.md"
_CRUSH_SECTION_START="<!-- BEGIN AGENTIC-SKILLS (managed — do not edit manually) -->"
_CRUSH_SECTION_END="<!-- END AGENTIC-SKILLS -->"

_rebuild_crush_md() {
    local tmp_section
    tmp_section="$(mktemp)"

    {
        echo "$_CRUSH_SECTION_START"
        for f in "$CRUSH_RULES_STAGING"/*.md; do
            [[ -f "$f" ]] || continue
            echo ""
            cat "$f"
            echo ""
        done
        echo "$_CRUSH_SECTION_END"
    } > "$tmp_section"

    mkdir -p "$(dirname "$CRUSH_MD")"

    if [[ ! -f "$CRUSH_MD" ]]; then
        cp "$tmp_section" "$CRUSH_MD"
        rm "$tmp_section"
        return
    fi

    if grep -qF "$_CRUSH_SECTION_START" "$CRUSH_MD"; then
        python3 - "$CRUSH_MD" "$tmp_section" << 'PYEOF'
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
        { echo ""; cat "$tmp_section"; } >> "$CRUSH_MD"
    fi

    rm "$tmp_section"
}

_remove_crush_section() {
    [[ ! -f "$CRUSH_MD" ]] && return
    grep -qF "$_CRUSH_SECTION_START" "$CRUSH_MD" || return

    python3 - "$CRUSH_MD" << 'PYEOF'
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

finalize_crush() {
    local has_rules=0
    if compgen -G "$CRUSH_RULES_STAGING/*.md" &>/dev/null; then
        has_rules=1
    fi

    if [[ $has_rules -eq 1 ]]; then
        if [[ ! -f "$CRUSH_MD" ]] || ! grep -qF "$_CRUSH_SECTION_START" "$CRUSH_MD"; then
            echo "    ! CRUSH.md managed section missing — rebuilding"
            _rebuild_crush_md
        fi
    else
        if [[ -f "$CRUSH_MD" ]] && grep -qF "$_CRUSH_SECTION_START" "$CRUSH_MD"; then
            echo "    ! CRUSH.md has stale managed section (no rules) — cleaning"
            _remove_crush_section
        fi
    fi
}

# Rules → staged then merged into CRUSH.md
get_crush_rule_dest()    { echo "$CRUSH_RULES_STAGING/${1}.md"; }

install_crush_rule() {
    local name="$1"
    local source_file="$2"
    mkdir -p "$CRUSH_RULES_STAGING"
    cp "$source_file" "$CRUSH_RULES_STAGING/${name}.md"
    _rebuild_crush_md
}

uninstall_crush_rule() {
    local name="$1"
    rm -f "$CRUSH_RULES_STAGING/${name}.md"
    if compgen -G "$CRUSH_RULES_STAGING/*.md" &>/dev/null; then
        _rebuild_crush_md
    else
        _remove_crush_section
    fi
}

# Skills + Commands → individual files in ~/.config/crush/skills/
get_crush_dest()         { echo "$CRUSH_SKILLS_DIR/${1}.md"; }

install_crush_skill() {
    local skill_name="$1"
    local source_file="$2"
    mkdir -p "$CRUSH_SKILLS_DIR"
    cp "$source_file" "$CRUSH_SKILLS_DIR/${skill_name}.md"
}

uninstall_crush_skill() {
    rm -f "$CRUSH_SKILLS_DIR/${1}.md"
}

get_crush_command_dest()   { get_crush_dest "$1"; }
install_crush_command()    { install_crush_skill "$@"; }
uninstall_crush_command()  { uninstall_crush_skill "$@"; }
