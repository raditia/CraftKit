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
_CLAUDE_AGENT_RULES_START="<!-- BEGIN CRAFTKIT-INJECTED-RULES (managed — regenerated on sync from rules/ or skills/) -->"
_CLAUDE_AGENT_RULES_END="<!-- END CRAFTKIT-INJECTED-RULES -->"

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

# Hooks spawn under a stripped PATH with no shell profile, so the registered command must
# carry an absolute interpreter. Which absolute path matters: prefer one a package manager
# repoints on upgrade over a version-pinned one, because fnm prunes old versions and a
# UserPromptSubmit hook that dies takes the whole routing gate with it, silently.
_resolve_node_bin() {
    local p
    for p in /opt/homebrew/bin/node /usr/local/bin/node; do
        [[ -x "$p" ]] && { echo "$p"; return; }
    done

    local fnm_dir="$HOME/.local/share/fnm/node-versions"
    if [[ -d "$fnm_dir" ]]; then
        # Highest version available — pinned, so _craftkit_hook_wire_settings migrates off
        # this the moment a managed path appears.
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
import json, os, re, sys
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
with open(settings_path) as f:
    settings = json.load(f)
hook = {'type': 'command', 'command': hook_cmd, 'timeout': 5, 'statusMessage': 'CraftKit routing...'}
ups = settings.setdefault('hooks', {}).setdefault('UserPromptSubmit', [])


def interpreter(cmd):
    m = re.match(r'"([^"]+)"', cmd)
    return m.group(1) if m else (cmd.split() or [''])[0]


# Registration used to be write-once, which meant the interpreter path was frozen at
# whatever existed on install day. Two ways that goes wrong, both re-pointed here:
# the path stopped existing (dead hook, no routing gate, no error the user would notice),
# or it is a version-pinned fnm path that is one `fnm uninstall` away from becoming the
# first case. A working non-pinned command is left alone — it may be deliberate.
for entry in ups:
    for h in entry.get('hooks', []):
        cmd = h.get('command', '')
        if 'craftkit-routing' not in cmd:
            continue
        current = interpreter(cmd)
        alive = os.path.isfile(current) and os.access(current, os.X_OK)
        pinned = 'fnm/node-versions' in current or 'fnm_multishells' in current
        if alive and not pinned:
            sys.exit(0)
        h['command'] = hook_cmd
        with open(settings_path, 'w') as f:
            json.dump(settings, f, indent=2)
            f.write('\n')
        print('    routing hook interpreter re-pointed: %s -> %s'
              % (current, interpreter(hook_cmd)))
        sys.exit(0)
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
        echo "    + hook: craftkit-routing"
    fi
    # Wired on every sync, not only when the script content changed. Registration is
    # idempotent and now repairs a stale interpreter, so gating it on the copy meant the
    # repair could never reach a machine whose hook script was already up to date —
    # which is every machine that had synced once.
    _craftkit_hook_wire_settings "$dest"
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

# Reads the comma-separated source names from an agent's `craftkitInject:` frontmatter
# line (only inside the leading --- block). Empty output = no injection requested.
_claude_agent_inject_list() {
    awk '
        NR==1 && $0=="---" { infm=1; next }
        infm && $0=="---" { exit }
        infm && /^craftkitInject:/ { sub(/^craftkitInject:[[:space:]]*/, ""); print; exit }
    ' "$1"
}

# Prints a markdown file with its leading YAML frontmatter stripped.
_claude_strip_frontmatter() {
    awk '
        NR==1 && $0=="---" { infm=1; next }
        infm && $0=="---" { infm=0; next }
        !infm { print }
    ' "$1"
}

# Renders an agent source file into $out. If the agent opts in via
# `craftkitInject: ruleA, skillB`, the bodies of rules/<ruleA>.md /
# skills/<skillB>/SKILL.md ... are spliced in as a managed block right after the
# agent's frontmatter — so cold agents carry the live text instead of a
# hand-maintained copy. No opt-in → plain copy.
_claude_render_agent() {
    local src="$1" out="$2"
    local list
    list="$(_claude_agent_inject_list "$src")"
    if [[ -z "$list" ]]; then
        cp "$src" "$out"
        return
    fi

    local block
    block="$(mktemp)"
    {
        echo "$_CLAUDE_AGENT_RULES_START"
        echo "$list" | tr ',' '\n' | while IFS= read -r r; do
            r="$(echo "$r" | tr -d '[:space:]')"
            [[ -z "$r" ]] && continue
            # rules/ wins over skills/ when a name exists in both
            if [[ -f "$RULES_DIR/${r}.md" ]]; then
                echo ""
                _claude_strip_frontmatter "$RULES_DIR/${r}.md"
            elif [[ -f "$SKILLS_DIR/${r}/SKILL.md" ]]; then
                echo ""
                _claude_strip_frontmatter "$SKILLS_DIR/${r}/SKILL.md"
            else
                echo "    ! craftkitInject: '$r' not found in rules/ or skills/ — skipped" >&2
            fi
        done
        echo ""
        echo "$_CLAUDE_AGENT_RULES_END"
    } > "$block"

    awk -v blockfile="$block" '
        BEGIN { while ((getline line < blockfile) > 0) blk = blk line "\n" }
        NR==1 && $0=="---" { infm=1; print; next }
        infm && $0=="---" { print; printf "\n%s", blk; infm=0; next }
        { print }
    ' "$src" > "$out"
    rm -f "$block"
}

# Optional currency hook used by sync.sh's agent loop: renders the agent to a temp
# file so the diff-skip check compares dest against the *rendered* output, not the
# raw source. sync.sh removes the returned temp file after diffing.
effective_claude_agent_source() {
    local source_file="$2"
    local tmp
    tmp="$(mktemp)"
    _claude_render_agent "$source_file" "$tmp"
    echo "$tmp"
}

install_claude_agent() {
    local name="$1"
    local source_file="$2"
    mkdir -p "$CLAUDE_AGENTS_DIR"
    _claude_render_agent "$source_file" "$CLAUDE_AGENTS_DIR/${name}.md"
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
