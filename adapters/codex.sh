#!/usr/bin/env bash
# Native Codex skills keep workflow bodies out of the global instruction budget.
# ~/.agents/skills is also Cursor's skill install and is read by Gemini CLI, so descriptions
# stay as authored: Codex shortens them itself within its budget.

CODEX_SKILLS_DIR="$HOME/.agents/skills"
CODEX_RULES_DIR="$HOME/.craftkit/codex/rules"
CODEX_AGENTS_MD="$HOME/.codex/AGENTS.md"
_CODEX_SECTION_START="<!-- BEGIN CRAFTKIT (managed: do not edit manually) -->"
_CODEX_SECTION_END="<!-- END CRAFTKIT -->"

_rebuild_codex_agents_md() {
    local tmp_section f
    tmp_section="$(mktemp)"
    {
        echo "$_CODEX_SECTION_START"
        cat <<'EOF'
# CraftKit for Codex

Use the installed CraftKit skills when their descriptions match the task. Invoke one explicitly with `$skill-name` when useful. Build, review, and ship workflows are skills too. Read only relevant skills.
For a workflow that requires a named Claude `subagent_type`, use its sequential twin: `parallel-build` to `build`, `parallel-review` to `review`, or `parallel-ship` to `ship`.

Working agreements:
- Ground findings and edits in files or command output checked during this task.
- Make the smallest change that fulfills the request; verify affected behavior before reporting completion.
- For flag-gated changes, preserve and verify behavior with the flag off.
- Follow the current project's AGENTS.md for project-specific conventions.

Full rule references, read when relevant:
EOF
        for f in "$CODEX_RULES_DIR"/*.md; do
            [[ -f "$f" ]] || continue
            printf -- '- %s: %s\n' "$(basename "$f" .md)" "$f"
        done
        echo "$_CODEX_SECTION_END"
    } > "$tmp_section"
    mkdir -p "$(dirname "$CODEX_AGENTS_MD")"
    if [[ ! -f "$CODEX_AGENTS_MD" ]]; then
        cp "$tmp_section" "$CODEX_AGENTS_MD"
    elif grep -qF "$_CODEX_SECTION_START" "$CODEX_AGENTS_MD"; then
        python3 - "$CODEX_AGENTS_MD" "$tmp_section" <<'PYEOF'
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
        { echo ""; cat "$tmp_section"; } >> "$CODEX_AGENTS_MD"
    fi
    rm -f "$tmp_section"
}

_remove_codex_section() {
    [[ ! -f "$CODEX_AGENTS_MD" ]] && return
    grep -qF "$_CODEX_SECTION_START" "$CODEX_AGENTS_MD" || return
    python3 - "$CODEX_AGENTS_MD" <<'PYEOF'
import re, sys
md_path = sys.argv[1]
with open(md_path) as f:
    content = f.read()
new_content = re.sub(
    r'\n?<!-- BEGIN CRAFTKIT .*?<!-- END CRAFTKIT -->\n?',
    '', content, flags=re.DOTALL,
)
with open(md_path, 'w') as f:
    f.write(new_content)
PYEOF
}

finalize_codex() {
    if compgen -G "$CODEX_RULES_DIR/*.md" &>/dev/null; then
        if [[ ! -f "$CODEX_AGENTS_MD" ]] || ! grep -qF "$_CODEX_SECTION_START" "$CODEX_AGENTS_MD"; then
            echo "    ! AGENTS.md managed section missing, rebuilding"
            _rebuild_codex_agents_md
        fi
    else
        _remove_codex_section
    fi
}

get_codex_dest() { echo "$CODEX_SKILLS_DIR/$1/SKILL.md"; }

codex_skill_collision() {
    local dest dir
    dest="$(get_codex_dest "$1")"
    dir="$(dirname "$dest")"
    [[ -L "$dir" || -L "$dest" ]] && return 0
    [[ -e "$dir" && ! -f "$dir/.craftkit-managed" ]]
}

install_codex_skill() {
    local name="$1" source_file="$2" dest
    dest="$(get_codex_dest "$name")"
    if codex_skill_collision "$name"; then
        echo "Codex skill collision at $dest; refusing to overwrite" >&2
        return 1
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$source_file" "$dest"
    touch "$(dirname "$dest")/.craftkit-managed"
}
uninstall_codex_skill() {
    local dest
    dest="$(get_codex_dest "$1")"
    [[ -f "$(dirname "$dest")/.craftkit-managed" ]] || return 0
    rm -f "$dest" "$(dirname "$dest")/.craftkit-managed"
    rmdir "$(dirname "$dest")" 2>/dev/null || true
}

get_codex_rule_dest() { echo "$CODEX_RULES_DIR/$1.md"; }
install_codex_rule() {
    mkdir -p "$CODEX_RULES_DIR"
    cp "$2" "$(get_codex_rule_dest "$1")"
    _rebuild_codex_agents_md
}
uninstall_codex_rule() {
    rm -f "$(get_codex_rule_dest "$1")"
    _rebuild_codex_agents_md
}

get_codex_command_dest() { get_codex_dest "$1"; }
install_codex_command() { install_codex_skill "$@"; }
uninstall_codex_command() { uninstall_codex_skill "$1"; }
