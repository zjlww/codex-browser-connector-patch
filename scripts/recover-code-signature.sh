#!/bin/bash
# Recover the ChatGPT/Codex app bundle after the failed Electron host-route
# patch, so the app boots again.
#
# The patch wrote 32 bytes into the Codex Framework's __DATA_CONST,__asar_integrity
# section. That invalidates the binary's code signature, and macOS then SIGKILLs
# any process that maps one of its pages -- which is why the app now dies inside
# dlopen with "CODESIGNING, Code 2 Invalid Page". Consequences for this script:
#
#   * nothing here may mmap the framework (a plain read() is fine);
#   * the framework is replaced by an ATOMIC RENAME, never written in place.
#
# All three artifacts must go back together: the asar contents, the Info.plist
# hash that covers the asar header, and the framework digest that covers the
# Info.plist dictionary.
set -uo pipefail

APP="/Applications/ChatGPT.app"
BK="$HOME/.local/share/codex-rollback/appbundle-orig"
RES="$APP/Contents/Resources"
PLIST="$APP/Contents/Info.plist"
FW="$APP/Contents/Frameworks/Codex Framework.framework/Versions/154.0.8037.57/Codex Framework"

for f in "$BK/Codex Framework" "$BK/Info.plist" "$BK/app.asar"; do
    [ -f "$f" ] || { echo "FATAL: missing backup $f" >&2; exit 1; }
done

echo "=== quitting the app ==="
pkill -TERM -f "$APP/Contents/" >/dev/null 2>&1
sleep 3

echo "=== framework (copy aside, then atomic rename) ==="
cp "$BK/Codex Framework" "$FW.restore-tmp" || { echo "FATAL: copy failed" >&2; exit 1; }
chmod 755 "$FW.restore-tmp"
mv -f "$FW.restore-tmp" "$FW" || { echo "FATAL: rename failed" >&2; exit 1; }
echo "restored $FW"

echo "=== Info.plist ==="
cp "$BK/Info.plist" "$PLIST.restore-tmp" || { echo "FATAL: copy failed" >&2; exit 1; }
mv -f "$PLIST.restore-tmp" "$PLIST" || { echo "FATAL: rename failed" >&2; exit 1; }
echo "restored $PLIST"

echo "=== app.asar ==="
cp "$BK/app.asar" "$RES/app.asar.restore-tmp" || { echo "FATAL: copy failed" >&2; exit 1; }
mv -f "$RES/app.asar.restore-tmp" "$RES/app.asar" || { echo "FATAL: rename failed" >&2; exit 1; }
echo "restored $RES/app.asar"

echo "=== relaunching ==="
open -a "$APP"
sleep 20
if pgrep -f "$APP/Contents/MacOS/ChatGPT" >/dev/null; then
    echo "ChatGPT is running."
else
    echo "WARNING: ChatGPT is not running; check Console.app."
fi
