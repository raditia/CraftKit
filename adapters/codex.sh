#!/usr/bin/env bash
# Codex CLI adapter.
#
# Codex has no slash command system — all rules, skills, and commands are
# concatenated into a managed block in ~/.codex/AGENTS.md (32 KiB total limit).
# Staging dir: ~/.craftkit/codex/

CODEX_STAGING_DIR="$HOME/.craftkit/codex"
CODEX_AGENTS_MD="$HOME/.codex/AGENTS.md"
_CODEX_SECTION_START="<!-- BEGIN AGENTIC-SKILLS (managed — do not edit manually) -->"
_CODEX_SECTION_END="<!-- END AGENTIC-SKILLS -->"

_rebuild_codex_agents_md() {
    local tmp_section
    tmp_section="$(mktemp)"

    {
        echo "$_CODEX_SECTION_START"
        for f in "$CODEX_STAGING_DIR"/*.md; do
            [[ -f "$f" ]] || continue
            echo ""
            cat "$f"
            echo ""
        done
        echo "$_CODEX_SECTION_END"
    } > "$tmp_section"

    mkdir -p "$(dirname "$CODEX_AGENTS_MD")"

    if [[ ! -f "$CODEX_AGENTS_MD" ]]; then
        cp "$tmp_section" "$CODEX_AGENTS_MD"
        rm "$tmp_section"
        return
    fi

    if grep -qF "$_CODEX_SECTION_START" "$CODEX_AGENTS_MD"; then
        python3 - "$CODEX_AGENTS_MD" "$tmp_section" << 'PYEOF'
import re, sys
md_path, section_path = sys.argv[1], sys.argv[2]
with open(md_path) as f:
    content = f.read()
with open(section_path) as f:
    replacement = f.read().strip()
new_content = re.sub(
    r'<!-- BEGIN AGENTIC-SKILLS.*?<!-- END AGENTIC-SKILLS -->',
    lambda _: replacement,
    content,
    flags=re.DOTALL,
)
with open(md_path, 'w') as f:
    f.write(new_content)
PYEOF
    else
        { echo ""; cat "$tmp_section"; } >> "$CODEX_AGENTS_MD"
    fi

    rm "$tmp_section"
}

_remove_codex_section() {
    [[ ! -f "$CODEX_AGENTS_MD" ]] && return
    grep -qF "$_CODEX_SECTION_START" "$CODEX_AGENTS_MD" || return

    python3 - "$CODEX_AGENTS_MD" << 'PYEOF'
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

finalize_codex() {
    local has_content=0
    if compgen -G "$CODEX_STAGING_DIR/*.md" &>/dev/null; then
        has_content=1
    fi

    if [[ $has_content -eq 1 ]]; then
        if [[ ! -f "$CODEX_AGENTS_MD" ]] || ! grep -qF "$_CODEX_SECTION_START" "$CODEX_AGENTS_MD"; then
            echo "    ! AGENTS.md managed section missing — rebuilding"
            _rebuild_codex_agents_md
        fi
    else
        if [[ -f "$CODEX_AGENTS_MD" ]] && grep -qF "$_CODEX_SECTION_START" "$CODEX_AGENTS_MD"; then
            echo "    ! AGENTS.md has stale managed section (no content) — cleaning"
            _remove_codex_section
        fi
    fi
}

get_codex_dest()    { echo "$CODEX_STAGING_DIR/${1}.md"; }

install_codex_skill() {
    local skill_name="$1"
    local source_file="$2"
    mkdir -p "$CODEX_STAGING_DIR"
    cp "$source_file" "$CODEX_STAGING_DIR/${skill_name}.md"
    _rebuild_codex_agents_md
}

uninstall_codex_skill() {
    local skill_name="$1"
    rm -f "$CODEX_STAGING_DIR/${skill_name}.md"
    if compgen -G "$CODEX_STAGING_DIR/*.md" &>/dev/null; then
        _rebuild_codex_agents_md
    else
        _remove_codex_section
    fi
}

get_codex_rule_dest()      { get_codex_dest "$1"; }
install_codex_rule()       { install_codex_skill "$@"; }
uninstall_codex_rule()     { uninstall_codex_skill "$@"; }

get_codex_command_dest()   { get_codex_dest "$1"; }
install_codex_command()    { install_codex_skill "$@"; }
uninstall_codex_command()  { uninstall_codex_skill "$@"; }
