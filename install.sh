#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || [[ "${BASH_VERSINFO[0]}" -eq 3 && "${BASH_VERSINFO[1]}" -lt 2 ]]; then
    echo "Error: bash 3.2+ required (got ${BASH_VERSION})"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing craftkit..."

# Install git post-merge hook so 'git pull' auto-syncs + installs tools
cp "$REPO_DIR/hooks/post-merge" "$REPO_DIR/.git/hooks/post-merge"
chmod +x "$REPO_DIR/.git/hooks/post-merge"
echo "    git post-merge hook installed"

# sync.sh handles tool installation (rtk, caveman) + skill sync
# AGENTIC_SETUP=1 tells sync.sh this is an explicit install — run ensure_tools
AGENTIC_SETUP=1 "$REPO_DIR/sync.sh"

echo ""
echo "Done. 'git pull' will now auto-sync skills and keep tools up to date."
