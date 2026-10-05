#!/usr/bin/env bash
# Entry point for context-source.js. Skills on every host call this path, and only Claude's
# hooks resolve node for themselves, so the wrapper finds an interpreter the same way
# adapters/claude.sh:_resolve_node_bin does. Exit 3 means no node, which callers report as
# cannot-verify instead of treating the source as empty.
set -uo pipefail

node_bin=""
for p in /opt/homebrew/bin/node /usr/local/bin/node; do
    [[ -x "$p" ]] && { node_bin="$p"; break; }
done
if [[ -z "$node_bin" ]]; then
    node_bin="$(command -v node 2>/dev/null)"
fi
if [[ -z "$node_bin" && -d "$HOME/.local/share/fnm/node-versions" ]]; then
    v="$(ls -1 "$HOME/.local/share/fnm/node-versions" | sort -V | tail -1)"
    p="$HOME/.local/share/fnm/node-versions/$v/installation/bin/node"
    [[ -x "$p" ]] && node_bin="$p"
fi
[[ -n "$node_bin" ]] || { echo "context-source: node not found" >&2; exit 3; }

exec "$node_bin" "$(dirname "${BASH_SOURCE[0]}")/context-source.js" "$@"
