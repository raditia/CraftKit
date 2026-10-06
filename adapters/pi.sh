#!/usr/bin/env bash
# pi (pi.dev): rules only. Skills and commands already reach pi through ~/.agents/skills,
# which the Codex adapter installs, and pi has no subagents, so there is no agent pass.
# pi has no hook loading rule bodies on demand, so always-on rules go inline into the
# managed block of <agent-dir>/AGENTS.md. using-agent-skills is Claude-shaped (Agent tool,
# hooks, parallel workflows) and is replaced outright by the short pi runtime guide, with no
# pointer, since following it would contradict the guide. Platform-scoped rules stay as
# pointers, since pi cannot scope a context file to a platform.

PI_RULES_DIR="$HOME/.craftkit/pi/rules"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PI_AGENTS_MD="$PI_AGENT_DIR/AGENTS.md"
_PI_SECTION_START="<!-- BEGIN CRAFTKIT (managed: do not edit manually) -->"
_PI_SECTION_END="<!-- END CRAFTKIT -->"

_pi_rule_platform() {
    awk 'NR==1&&$0=="---"{fm=1;next} fm&&$0=="---"{exit} fm&&/^platform:/{sub(/^platform:[[:space:]]*/,"");print;exit}' "$1"
}

_pi_render_section() {
    local f name plat
    echo "$_PI_SECTION_START"
    cat <<'EOF'
# CraftKit for pi

Classify task intent against the installed skill descriptions before work. Announce the selected skill and follow its `SKILL.md` (force one with `/skill:name`). If no skill matches, say so in one line and proceed. User instructions take precedence.
pi has no subagents, so build, review, and ship run the sequential twins: `build`, `review`, `ship` (never `parallel-*` or `team-build`). Broken behavior uses `fix`; planning uses `define`; test authoring uses the platform's test skill; PR descriptions use `pr-message`.
Use `rtk` for supported shell commands. Before reporting completion, run the project's verification gates on the latest edits and report the actual output. Findings use `[ERROR]` (must fix), `[WARNING]` (should fix), `[SUGGESTION]` (optional).
EOF
    local pointers=""
    for f in "$PI_RULES_DIR"/*.md; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f" .md)"
        plat="$(_pi_rule_platform "$f")"
        if [[ "$name" == "using-agent-skills" ]]; then
            continue
        elif [[ -n "$plat" ]]; then
            pointers="${pointers}- ${name} (read when the project platform is ${plat}): ${f}"$'\n'
        else
            echo ""
            craftkit_strip_frontmatter "$f"
        fi
    done
    if [[ -n "$pointers" ]]; then
        echo ""
        echo "Rule references, read when relevant:"
        printf '%s' "$pointers"
    fi
    echo "$_PI_SECTION_END"
}

# Writes only on a content change, so a repeat sync leaves AGENTS.md untouched.
_rebuild_pi_agents_md() {
    local tmp_section tmp_out
    tmp_section="$(mktemp)"
    _pi_render_section > "$tmp_section"
    if [[ ! -f "$PI_AGENTS_MD" ]]; then
        cp "$tmp_section" "$PI_AGENTS_MD"
        echo "    + pi AGENTS.md managed block"
    else
        tmp_out="$(mktemp)"
        python3 - "$PI_AGENTS_MD" "$tmp_section" "$tmp_out" <<'PYEOF' || { rm -f "$tmp_section" "$tmp_out"; return 1; }
import re, sys
md_path, section_path, out_path = sys.argv[1:4]
content = open(md_path, encoding='utf-8').read()
section = open(section_path, encoding='utf-8').read().strip()
pattern = r'<!-- BEGIN CRAFTKIT .*?<!-- END CRAFTKIT -->'
if re.search(pattern, content, flags=re.DOTALL):
    content = re.sub(pattern, lambda _: section, content, flags=re.DOTALL)
else:
    content = content.rstrip('\n') + '\n\n' + section + '\n'
open(out_path, 'w', encoding='utf-8').write(content)
PYEOF
        # -s: an empty render must never replace the user's file.
        if [[ -s "$tmp_out" ]] && ! cmp -s "$tmp_out" "$PI_AGENTS_MD"; then
            cat "$tmp_out" > "$PI_AGENTS_MD"
            echo "    + pi AGENTS.md managed block"
        fi
        rm -f "$tmp_out"
    fi
    rm -f "$tmp_section"
}

_remove_pi_section() {
    [[ -f "$PI_AGENTS_MD" ]] && grep -qF "$_PI_SECTION_START" "$PI_AGENTS_MD" || return 0
    python3 - "$PI_AGENTS_MD" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
open(p, 'w', encoding='utf-8').write(re.sub(r'\n?<!-- BEGIN CRAFTKIT .*?<!-- END CRAFTKIT -->\n?', '', s, flags=re.DOTALL))
PYEOF
    echo "    - pi AGENTS.md managed block"
}

# The agent dir exists only once pi is installed and run, so a user without pi gets no
# ~/.pi created. Installing pi later is picked up by the next sync, since finalize rebuilds.
finalize_pi() {
    [[ -d "$PI_AGENT_DIR" ]] || return 0
    if compgen -G "$PI_RULES_DIR/*.md" &>/dev/null; then
        _rebuild_pi_agents_md
    else
        _remove_pi_section
    fi
}

get_pi_rule_dest() { echo "$PI_RULES_DIR/${1}.md"; }

install_pi_rule() {
    mkdir -p "$PI_RULES_DIR"
    cp "$2" "$PI_RULES_DIR/${1}.md"
}

uninstall_pi_rule() { rm -f "$PI_RULES_DIR/${1}.md"; }
