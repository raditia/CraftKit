#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "Error: bash 4+ required. On macOS: brew install bash"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing agentic-skills..."

# Install git post-merge hook so 'git pull' auto-syncs
cp "$REPO_DIR/hooks/post-merge" "$REPO_DIR/.git/hooks/post-merge"
chmod +x "$REPO_DIR/.git/hooks/post-merge"
echo "    git post-merge hook installed"

# Run initial sync
"$REPO_DIR/sync.sh"

echo ""
echo "Done. Future 'git pull' will auto-sync skills."
