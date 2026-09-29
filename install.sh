#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || [[ "${BASH_VERSINFO[0]}" -eq 3 && "${BASH_VERSINFO[1]}" -lt 2 ]]; then
    echo "Error: bash 3.2+ required (got ${BASH_VERSION})"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing craftkit..."

# Install hooks for merge and rebase pulls.
if [[ -d "$REPO_DIR/.git" ]]; then
    for hook in post-merge post-rewrite; do
        cp "$REPO_DIR/hooks/$hook" "$REPO_DIR/.git/hooks/$hook"
        chmod +x "$REPO_DIR/.git/hooks/$hook"
        echo "    git $hook hook installed"
    done
else
    echo "    git hooks skipped (not a git repo)"
fi

# sync.sh handles tool installation (rtk, caveman) + skill sync
# AGENTIC_SETUP=1 tells sync.sh this is an explicit install, so run ensure_tools
AGENTIC_SETUP=1 "$REPO_DIR/sync.sh"

echo ""
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "Done. Merge and rebase pulls will now auto-sync skills and keep tools up to date."
else
    echo "Done. Run 'npm install -g @raditia/craftkit' to update, or pin a version with '@raditia/craftkit@x.y.z'."
fi
