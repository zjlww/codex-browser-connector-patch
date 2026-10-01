#!/bin/bash
# Apply every browser-connector patch INCLUDING the Electron host route (gate 5),
# then make the modified framework loadable by re-signing the app ad-hoc.
#
# Why the re-sign is unavoidable: editing a file inside app.asar forces an
# update to the Codex Framework's __asar_integrity digest, which invalidates
# that binary's code signature; dyld then refuses to load it ("CODESIGNING,
# Code 2 Invalid Page"). Re-signing the bundle ad-hoc with
# com.apple.security.cs.disable-library-validation makes it self-consistent.
#
# The restricted entitlements (application-identifier, team-identifier, app
# groups, keychain-access-groups, aps-environment) are deliberately DROPPED:
# they need a provisioning profile we do not have, and with them present the
# kernel silently refuses to exec the app at all. Consequences of dropping
# them: push notifications, app-group sharing and keychain-group sharing stop
# working.
#
# If the app does not come back up, the host changes are rolled back
# automatically, so this cannot leave you with a non-booting app.
#
# Run from Terminal.app: writing inside /Applications/ChatGPT.app needs the
# macOS App Management permission, which DeepSeek Harness does not have.
set -uo pipefail

SCRIPTS="$HOME/.local/share/codex-rollback"
PATCHER="$SCRIPTS/patch-browser-connector.py"
APP="/Applications/ChatGPT.app"
LOG="$SCRIPTS/apply-verify.log"
ENT="$SCRIPTS/host-route-entitlements.plist"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
app_pid() { pgrep -f "$APP/Contents/MacOS/ChatGPT" | head -1; }

quit_all() {
    pkill -TERM -f "$APP/Contents/" >/dev/null 2>&1
    for _ in $(seq 1 8); do [ -z "$(app_pid)" ] && break; sleep 1; done
    pkill -KILL -f "$APP/Contents/" >/dev/null 2>&1
    sleep 3
}

cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><false/>
<key>com.apple.security.automation.apple-events</key><true/>
<key>com.apple.security.cs.allow-jit</key><true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
<key>com.apple.security.cs.disable-library-validation</key><true/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.personal-information.calendars</key><true/>
</dict></plist>
PLIST

log "=== apply-host-route start ==="
quit_all
log "app stopped (remaining processes: $(pgrep -f "$APP/Contents/" | wc -l | tr -d ' '))"

/usr/bin/python3 "$PATCHER" --apply >>"$LOG" 2>&1
# The exit code is not trustworthy here: writing the framework digest can make
# the kernel kill the writer, and it can die *after* the write has landed. Ask
# the patcher what the on-disk state actually is instead.
HOST_STATUS="$(/usr/bin/python3 "$PATCHER" --check 2>/dev/null | awk '/Resources\/app\.asar$/{print $1}')"
log "host route status after apply: ${HOST_STATUS:-unknown}"
if [ "$HOST_STATUS" != "patched" ]; then
    log "ERROR: host route is not applied (${HOST_STATUS:-unknown}); see $LOG"
    open -a "$APP"
    exit 1
fi
log "patches applied (asar, Info.plist, framework digest)"

log "re-signing ad-hoc (this takes a couple of minutes)"
if ! codesign --force --deep --sign - --entitlements "$ENT" --options runtime "$APP" >>"$LOG" 2>&1; then
    log "ERROR: codesign failed; rolling the host route back"
    /usr/bin/python3 "$PATCHER" --restore-host >>"$LOG" 2>&1
    open -a "$APP"
    exit 1
fi
log "re-signed ad-hoc"

open -a "$APP"
sleep 30
PID="$(app_pid)"
if [ -n "$PID" ]; then
    sleep 12
    if [ "$PID" = "$(app_pid)" ]; then
        log "SUCCESS: app is up and stable with the host route patch (pid $PID)"
        exit 0
    fi
fi

log "FAILURE: app did not stay up; rolling the host route back"
quit_all
/usr/bin/python3 "$PATCHER" --restore-host >>"$LOG" 2>&1
open -a "$APP"
sleep 20
if [ -n "$(app_pid)" ]; then
    log "rolled back: app is running on the original host bundle"
else
    log "WARNING: app still not running; recover from $SCRIPTS/appbundle-orig"
fi
exit 1
