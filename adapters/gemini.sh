#!/usr/bin/env bash
# Gemini CLI: copies skill files to ~/.agentic-skills/gemini/ and maintains a
# managed AI-SKILLS section in ~/GEMINI.md (the global Gemini context file).

GEMINI_SKILLS_DIR="$HOME/.agentic-skills/gemini"
GEMINI_MD="$HOME/GEMINI.md"
_SECTION_START="<!-- BEGIN AGENTIC-SKILLS (managed — do not edit manually) -->"
_SECTION_END="<!-- END AGENTIC-SKILLS -->"

# Rebuilds the managed section in ~/GEMINI.md from all installed skill files
_rebuild_gemini_md() {
    local tmp_section
    tmp_section="$(mktemp)"

    {
        echo "$_SECTION_START"
        for f in "$GEMINI_SKILLS_DIR"/*.md; do
            [[ -f "$f" ]] || continue
            echo ""
            cat "$f"
            echo ""
        done
        echo "$_SECTION_END"
    } > "$tmp_section"

    if [[ ! -f "$GEMINI_MD" ]]; then
        cp "$tmp_section" "$GEMINI_MD"
        rm "$tmp_section"
        return
    fi

    if grep -qF "$_SECTION_START" "$GEMINI_MD"; then
        # Replace existing section using Python for reliable multi-line substitution
        python3 - "$GEMINI_MD" "$tmp_section" << 'PYEOF'
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
        # Append new section
        { echo ""; cat "$tmp_section"; } >> "$GEMINI_MD"
    fi

    rm "$tmp_section"
}

# Removes the managed section entirely when no skills remain
_remove_gemini_section() {
    [[ ! -f "$GEMINI_MD" ]] && return
    grep -qF "$_SECTION_START" "$GEMINI_MD" || return

    python3 - "$GEMINI_MD" << 'PYEOF'
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

# Called after every sync pass — rebuilds GEMINI.md if the managed section is
# missing or stale (e.g. file was manually edited or accidentally deleted).
finalize_gemini() {
    local has_skills=0
    if compgen -G "$GEMINI_SKILLS_DIR/*.md" &>/dev/null; then
        has_skills=1
    fi

    if [[ $has_skills -eq 1 ]]; then
        if [[ ! -f "$GEMINI_MD" ]] || ! grep -qF "$_SECTION_START" "$GEMINI_MD"; then
            echo "    ! GEMINI.md managed section missing — rebuilding"
            _rebuild_gemini_md
        fi
    else
        if [[ -f "$GEMINI_MD" ]] && grep -qF "$_SECTION_START" "$GEMINI_MD"; then
            echo "    ! GEMINI.md has stale managed section (no skills) — cleaning"
            _remove_gemini_section
        fi
    fi
}

get_gemini_dest() {
    local skill_name="$1"
    echo "$GEMINI_SKILLS_DIR/${skill_name}.md"
}

install_gemini_skill() {
    local skill_name="$1"
    local source_file="$2"
    mkdir -p "$GEMINI_SKILLS_DIR"
    cp "$source_file" "$GEMINI_SKILLS_DIR/${skill_name}.md"
    _rebuild_gemini_md
}

uninstall_gemini_skill() {
    local skill_name="$1"
    rm -f "$GEMINI_SKILLS_DIR/${skill_name}.md"
    if compgen -G "$GEMINI_SKILLS_DIR/*.md" &>/dev/null; then
        _rebuild_gemini_md
    else
        _remove_gemini_section
    fi
}

get_gemini_command_dest() { get_gemini_dest "$1"; }
install_gemini_command()   { install_gemini_skill "$@"; }
uninstall_gemini_command() { uninstall_gemini_skill "$@"; }
