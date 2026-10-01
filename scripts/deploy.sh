#!/bin/bash
# Deploy this project's scripts to the live location the app uses.
# Source of truth: this directory. Live copies: ~/.local/share/codex-rollback/
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.local/share/codex-rollback"

mkdir -p "$DEST"
cp "$SRC/codex-auth-shim.py" "$SRC/patch-browser-connector.py" "$SRC/restart-once.sh" \
   "$SRC/restore-appbundle.sh" "$SRC/restore-host-asar.sh" \
   "$SRC/recover-code-signature.sh" "$SRC/apply-host-route.sh" "$DEST/"
rm -f "$DEST/apply-and-verify.sh"   # superseded by apply-host-route.sh
chmod 755 "$DEST"/codex-auth-shim.py "$DEST"/patch-browser-connector.py \
          "$DEST"/restart-once.sh "$DEST"/restore-appbundle.sh \
          "$DEST"/restore-host-asar.sh "$DEST"/recover-code-signature.sh \
          "$DEST"/apply-host-route.sh
echo "deployed to $DEST:"
ls -la "$DEST"
