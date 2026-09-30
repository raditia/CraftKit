#!/usr/bin/env bash
# Native Codex skills keep workflow bodies out of the global instruction budget.
# ~/.agents/skills is also Cursor's skill install and is read by Gemini CLI, so descriptions
# stay as authored: Codex shortens them itself within its budget.

CODEX_SKILLS_DIR="$HOME/.agents/skills"
CODEX_RULES_DIR="$HOME/.craftkit/codex/rules"
CODEX_AGENTS_MD="$HOME/.codex/AGENTS.md"
CODEX_HOOKS_DIR="$HOME/.codex/hooks"
CODEX_HOOKS_CONFIG="$HOME/.codex/hooks.json"
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
The Codex SessionStart hook loads the full applicable rule bodies. Follow those instructions and the activated skill or command body. The Stop hook checks project verification after edits.

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
    install_codex_craftkit_hooks
    install_codex_dashboard_hook
}

# flag: CRAFTKIT_DASHBOARD (resolved in sync.sh). off: the agent-log hook is absent, and a sync removes one an earlier opted-in sync registered. remove: if the dashboard ever becomes default-on.
install_codex_dashboard_hook() {
    local on="${CRAFTKIT_DASHBOARD_ON:-0}" dest="$CODEX_HOOKS_DIR/craftkit-agent-log.js"
    if [[ "$on" == 1 ]]; then
        mkdir -p "$CODEX_HOOKS_DIR"
        if ! diff -q "$REPO_DIR/hooks/craftkit-agent-log.js" "$dest" &>/dev/null; then
            cp "$REPO_DIR/hooks/craftkit-agent-log.js" "$dest"
            echo "    + hook: craftkit-agent-log"
        fi
    fi
    # Unregistered before the script is deleted, so a failure here never leaves Codex
    # calling a hook whose file is gone.
    if [[ -f "$CODEX_HOOKS_CONFIG" || "$on" == 1 ]]; then
        python3 - "$CODEX_HOOKS_CONFIG" "$on" "$(_resolve_node_bin)" "$dest" <<'PYEOF' || return 0
import json, os, stat, sys
config, on, node, script = sys.argv[1], sys.argv[2] == '1', sys.argv[3], sys.argv[4]
EVENTS = ('SubagentStart', 'SubagentStop', 'PostToolUse', 'SessionEnd')
try:
    with open(config) as f:
        data = json.load(f)
    assert isinstance(data, dict) and isinstance(data.get('hooks', {}), dict)
    for event in EVENTS:
        groups = data.get('hooks', {}).get(event, [])
        assert isinstance(groups, list) and all(isinstance(g, dict) and isinstance(g.get('hooks', []), list) for g in groups)
except FileNotFoundError:
    data = {}
except (ValueError, AssertionError):
    print('    ! ~/.codex/hooks.json has a shape this sync does not recognise, agent-log hook left as is')
    sys.exit(3)  # non-zero, so the caller keeps the script a registration may still point at
command = json.dumps(node) + ' ' + json.dumps(script) + ' codex'
ours = lambda h: isinstance(h, dict) and 'craftkit-agent-log.js' in str(h.get('command', ''))
before = json.dumps(data, sort_keys=True)
had_hooks = 'hooks' in data
hooks = data.setdefault('hooks', {})
for event in EVENTS:
    current = hooks.get(event, [])
    if on and any(isinstance(h, dict) and h.get('command') == command for g in current for h in g.get('hooks', [])):
        continue
    groups = []
    for g in current:
        kept = [h for h in g.get('hooks', []) if not ours(h)]
        if kept or not g.get('hooks'):
            groups.append(dict(g, hooks=kept) if 'hooks' in g else g)
    if on:
        groups.append({'hooks': [{'type': 'command', 'command': command, 'timeout': 5}]})
    if groups:
        hooks[event] = groups
    else:
        hooks.pop(event, None)
if not hooks and not had_hooks:
    data.pop('hooks')
if json.dumps(data, sort_keys=True) != before:
    # Through the symlink and with the file's own mode, so a dotfiles link or a 0600 file survives.
    real = os.path.realpath(config)
    mode = stat.S_IMODE(os.stat(real).st_mode) if os.path.exists(real) else 0o600
    tmp = real + '.tmp'
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        os.replace(tmp, real)
    except BaseException:
        if os.path.exists(tmp): os.remove(tmp)
        raise
    print('    + Codex agent-log hook registered; review and trust it with /hooks' if on
          else '    - Codex agent-log hook unregistered')
PYEOF
    fi
    if [[ "$on" != 1 && -f "$dest" ]]; then
        rm -f "$dest"
        echo "    - hook: craftkit-agent-log"
    fi
    return 0
}

# Codex requires review and trust of each changed hook definition in /hooks. Keep the
# command stable across script updates, preserve unrelated hooks, and report review when
# this installer first registers the definition.
install_codex_craftkit_hooks() {
    local script dest node_bin
    mkdir -p "$CODEX_HOOKS_DIR"
    for script in craftkit-codex.js craftkit-platform.js; do
        dest="$CODEX_HOOKS_DIR/$script"
        if [[ ! -f "$dest" ]] || ! diff -q "$REPO_DIR/hooks/$script" "$dest" &>/dev/null; then
            cp "$REPO_DIR/hooks/$script" "$dest"
            echo "    + hook: ${script%.js}"
        fi
    done
    node_bin="$(_resolve_node_bin)"
    python3 - "$CODEX_HOOKS_CONFIG" "$node_bin" "$CODEX_HOOKS_DIR/craftkit-codex.js" <<'PYEOF'
import json, os, sys
config, node, script = sys.argv[1:]
try:
    with open(config) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
command = json.dumps(node) + ' ' + json.dumps(script)
changed = False
for event in ('SessionStart', 'UserPromptSubmit', 'PostToolUse', 'Stop'):
    groups = data.setdefault('hooks', {}).setdefault(event, [])
    found = False
    for group in groups:
        for hook in group.get('hooks', []):
            if 'craftkit-codex.js' in hook.get('command', ''):
                found = True
                if hook.get('command') != command:
                    hook['command'] = command
                    changed = True
    if not found:
        entry = {'type': 'command', 'command': command, 'timeout': 10}
        if event == 'SessionStart':
            entry['additionalContextLimit'] = 100000
        group = {'hooks': [entry]}
        if event == 'PostToolUse':
            group['matcher'] = 'Bash'
        groups.append(group)
        changed = True
if changed:
    with open(config, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('    + Codex hooks registered; review and trust them with /hooks')
PYEOF
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
