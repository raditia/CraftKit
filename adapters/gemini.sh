#!/usr/bin/env bash
# Gemini CLI: copies rule files to ~/.craftkit/gemini/ and maintains a managed section
# in ~/GEMINI.md (the global Gemini context file). Skills and commands reach Gemini as
# native skills through ~/.agents/skills, which the Codex adapter installs.

GEMINI_SKILLS_DIR="$HOME/.craftkit/gemini"
GEMINI_MD="$HOME/GEMINI.md"
_SECTION_START="<!-- BEGIN CRAFTKIT (managed: do not edit manually) -->"
_SECTION_END="<!-- END CRAFTKIT -->"

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
    r'<!-- BEGIN CRAFTKIT .*?<!-- END CRAFTKIT -->',
    lambda _: replacement,
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
    r'\n?<!-- BEGIN CRAFTKIT .*?<!-- END CRAFTKIT -->\n?',
    '',
    content,
    flags=re.DOTALL,
)

with open(md_path, 'w') as f:
    f.write(new_content)
PYEOF
}

# Called after every sync pass. Rebuilds GEMINI.md if the managed section is
# missing or stale (e.g. file was manually edited or accidentally deleted).
finalize_gemini() {
    local has_skills=0
    if compgen -G "$GEMINI_SKILLS_DIR/*.md" &>/dev/null; then
        has_skills=1
    fi

    if [[ $has_skills -eq 1 ]]; then
        if [[ ! -f "$GEMINI_MD" ]] || ! grep -qF "$_SECTION_START" "$GEMINI_MD"; then
            echo "    ! GEMINI.md managed section missing, rebuilding"
            _rebuild_gemini_md
        fi
    else
        if [[ -f "$GEMINI_MD" ]] && grep -qF "$_SECTION_START" "$GEMINI_MD"; then
            echo "    ! GEMINI.md has stale managed section (no skills), cleaning"
            _remove_gemini_section
        fi
    fi
}

get_gemini_rule_dest() { echo "$GEMINI_SKILLS_DIR/${1}.md"; }

install_gemini_rule() {
    mkdir -p "$GEMINI_SKILLS_DIR"
    cp "$2" "$(get_gemini_rule_dest "$1")"
    _rebuild_gemini_md
}

uninstall_gemini_rule() {
    rm -f "$(get_gemini_rule_dest "$1")"
    if compgen -G "$GEMINI_SKILLS_DIR/*.md" &>/dev/null; then
        _rebuild_gemini_md
    else
        _remove_gemini_section
    fi
}

# No installers: these take back the copies synced before skills moved to ~/.agents/skills.
uninstall_gemini_skill()   { uninstall_gemini_rule "$1"; }
uninstall_gemini_command() { uninstall_gemini_rule "$1"; }
