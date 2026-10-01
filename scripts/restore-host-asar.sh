#!/bin/bash
# Restore ONLY the Electron host bundle (Resources/app.asar) and the
# Info.plist integrity hash that guards it, from the copies taken before the
# browser-route patch. This is the recovery path when the host patch makes the
# app exit at launch with "ASAR Integrity Violation".
#
# It deliberately leaves browser-service.mjs and cua_node/bin/node_repl patched:
# those live outside the asar and are not integrity-checked. Use
# patch-browser-connector.py --restore for a full revert.
#
# Thin wrapper around the Python patcher, which owns the path list so the two
# cannot drift apart.
set -euo pipefail

exec /usr/bin/python3 /Users/zjlww/.local/share/codex-rollback/patch-browser-connector.py --restore-host
