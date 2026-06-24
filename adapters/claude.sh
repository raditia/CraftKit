#!/usr/bin/env bash
# Claude Code adapter.
#
# alwaysApply: true  → written into ~/.claude/CLAUDE.md (auto-loaded every session)
# alwaysApply: false → installed as ~/.claude/commands/<skill>.md (slash command)

CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
CLAUDE_AGENTS_DIR="$HOME/.claude/agents"
CLAUDE_HOOKS_DIR="$HOME/.claude/hooks"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_RULES_DIR="$HOME/.craftkit/claude-rules"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
_CRAFTKIT_HOOK_SCRIPT="craftkit-routing.js"
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
    lambda _: replacement,
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

_resolve_node_bin() {
    # Prefer fnm's stable installation path over session-scoped multishell symlink
    local fnm_dir="$HOME/.local/share/fnm/node-versions"
    if [[ -d "$fnm_dir" ]]; then
        # Pick highest version available
        local stable
        stable="$(ls -1 "$fnm_dir" | sort -V | tail -1)"
        local candidate="$fnm_dir/$stable/installation/bin/node"
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return
        fi
    fi
    command -v node 2>/dev/null || echo "node"
}

_craftkit_hook_wire_settings() {
    local hook_dest="$1"
    local node_bin
    node_bin="$(_resolve_node_bin)"
    local hook_cmd="\"${node_bin}\" \"${hook_dest}\""

    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        python3 -c "
import json
hook = {'type':'command','command':'${hook_cmd}','timeout':5,'statusMessage':'CraftKit routing...'}
print(json.dumps({'hooks':{'UserPromptSubmit':[{'hooks':[hook]}]}},indent=2))
" > "$CLAUDE_SETTINGS"
        return
    fi

    python3 - "$CLAUDE_SETTINGS" "$hook_cmd" << 'PYEOF'
import json, sys
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    settings = json.load(f)
hook = {'type': 'command', 'command': hook_cmd, 'timeout': 5, 'statusMessage': 'CraftKit routing...'}
ups = settings.setdefault('hooks', {}).setdefault('UserPromptSubmit', [])
for entry in ups:
    for h in entry.get('hooks', []):
        if 'craftkit-routing' in h.get('command', ''):
            sys.exit(0)  # already registered
if ups:
    ups[0].setdefault('hooks', []).append(hook)
else:
    ups.append({'hooks': [hook]})
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
PYEOF
}

_craftkit_hook_unwire_settings() {
    [[ ! -f "$CLAUDE_SETTINGS" ]] && return
    python3 - "$CLAUDE_SETTINGS" << 'PYEOF'
import json, sys
settings_path = sys.argv[1]
with open(settings_path) as f:
    settings = json.load(f)
ups = settings.get('hooks', {}).get('UserPromptSubmit', [])
for entry in ups:
    entry['hooks'] = [h for h in entry.get('hooks', []) if 'craftkit-routing' not in h.get('command', '')]
settings['hooks']['UserPromptSubmit'] = [e for e in ups if e.get('hooks')]
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')
PYEOF
}

install_claude_craftkit_hook() {
    local src="$REPO_DIR/hooks/$_CRAFTKIT_HOOK_SCRIPT"
    local dest="$CLAUDE_HOOKS_DIR/$_CRAFTKIT_HOOK_SCRIPT"
    [[ ! -f "$src" ]] && return
    mkdir -p "$CLAUDE_HOOKS_DIR"
    if [[ ! -f "$dest" ]] || ! diff -q "$src" "$dest" &>/dev/null; then
        cp "$src" "$dest"
        chmod +x "$dest"
        _craftkit_hook_wire_settings "$dest"
        echo "    + hook: craftkit-routing"
    fi
}

uninstall_claude_craftkit_hook() {
    local dest="$CLAUDE_HOOKS_DIR/$_CRAFTKIT_HOOK_SCRIPT"
    if [[ -f "$dest" ]]; then
        rm -f "$dest"
        _craftkit_hook_unwire_settings
        echo "    - hook: craftkit-routing"
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

    install_claude_craftkit_hook
}

get_claude_agent_dest() {
    echo "$CLAUDE_AGENTS_DIR/${1}.md"
}

install_claude_agent() {
    local name="$1"
    local source_file="$2"
    mkdir -p "$CLAUDE_AGENTS_DIR"
    cp "$source_file" "$CLAUDE_AGENTS_DIR/${name}.md"
}

uninstall_claude_agent() {
    rm -f "$CLAUDE_AGENTS_DIR/${1}.md"
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
