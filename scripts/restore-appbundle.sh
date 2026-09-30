#!/bin/bash
# Restore the patched files inside ChatGPT.app (browser-service.mjs copies and the
# node_repl wrapper). Thin wrapper around the Python patcher, which owns the path
# list so the two cannot drift apart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /usr/bin/python3 "$SCRIPT_DIR/patch-browser-connector.py" --restore
