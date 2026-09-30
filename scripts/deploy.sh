#!/bin/bash
# Deploy this project's scripts to the live location the app uses.
# Source of truth: this directory. Live copies: ~/.local/share/codex-rollback/
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${CODEX_BROWSER_ROLLBACK_DIR:-$HOME/.local/share/codex-rollback}"

mkdir -p "$DEST"
cp "$SRC/codex-auth-shim.py" "$SRC/patch-browser-connector.py" "$SRC/restart-once.sh" \
   "$SRC/restore-appbundle.sh" "$DEST/"
chmod 755 "$DEST"/codex-auth-shim.py "$DEST"/patch-browser-connector.py \
          "$DEST"/restart-once.sh "$DEST"/restore-appbundle.sh
echo "deployed to $DEST:"
ls -la "$DEST"
