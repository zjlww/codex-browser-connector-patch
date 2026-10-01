#!/bin/bash
# Restore the patched files inside ChatGPT.app (browser-service.mjs copies and the
# node_repl wrapper). Thin wrapper around the Python patcher, which owns the path
# list so the two cannot drift apart.
set -euo pipefail

exec /usr/bin/python3 /Users/zjlww/.local/share/codex-rollback/patch-browser-connector.py --restore
