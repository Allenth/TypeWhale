#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="/Applications/TypeWhale Pro.app"
INFO="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/TypeWhalePro"

test -d "$APP"
test -f "$INFO"
test -x "$BINARY"

source_build="$(perl -ne 'print "$1\n" if m{BundleVersion</key><string>([^<]+)}' "$ROOT/native/build_native_app.sh" | tail -1)"
installed_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO")"
test "$installed_build" = "$source_build"
test "$installed_build" -ge 903

codesign --verify --deep --strict "$APP"
grep -aFq 'hotkey_gesture phase=classified' "$BINARY"
grep -aFq 'remote_voice_control event=' "$BINARY"
grep -aFq 'remote_voice_f5 decision=' "$BINARY"
pgrep -x TypeWhalePro >/dev/null

print "TypeWhaleInputGestureRuntimeCheck passed: Build $installed_build signed and running"
