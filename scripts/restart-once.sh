#!/bin/bash
# Quit and relaunch the ChatGPT/Codex app exactly once.
# Launched detached (setsid) so it survives the app quitting; it does not use
# launchd, which keeps re-running submitted jobs.
set -uo pipefail

DEST="${CHATGPT_APP:-/Applications/ChatGPT.app}"
BUNDLE_RE="$DEST/Contents/"
ROLLBACK_DIR="${CODEX_BROWSER_ROLLBACK_DIR:-$HOME/.local/share/codex-rollback}"
LOG="$ROLLBACK_DIR/restart.log"

mkdir -p "$ROLLBACK_DIR"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }

log "=== restart-once start ==="
sleep 10

osascript -e 'quit app "ChatGPT"' >/dev/null 2>&1
for _ in $(seq 1 10); do
    pgrep -f "$BUNDLE_RE" >/dev/null 2>&1 || break
    sleep 1
done
if pgrep -f "$BUNDLE_RE" >/dev/null 2>&1; then
    log "graceful quit did not finish; sending SIGTERM"
    pkill -f "$BUNDLE_RE" >/dev/null 2>&1
    sleep 6
fi
log "app stopped"

if open -a "$DEST" >/dev/null 2>&1; then
    log "relaunched $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null)"
else
    log "WARNING: relaunch failed; open $DEST manually"
fi
log "=== restart-once done ==="
exit 0
