#!/bin/zsh
set -euo pipefail

APP="/Applications/TypeWhale Pro.app"
PLIST="$APP/Contents/Info.plist"

test -d "$APP"
test -f "$PLIST"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
test "$BUILD" -ge 900

/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/pgrep -f "$APP/Contents/MacOS/TypeWhalePro" >/dev/null

LOG="$HOME/Library/Logs/TypeWhale Pro/$(date +%F)/$VERSION-$BUILD.log"
test -f "$LOG"
/usr/bin/grep -Fq 'recording_stop_handoff phase=accepted' "$LOG"
/usr/bin/grep -Fq 'recording_stop_handoff phase=completed' "$LOG"

ACCEPTED_COUNT="$(/usr/bin/grep -Fc 'recording_stop_handoff phase=accepted' "$LOG")"
COMPLETED_COUNT="$(/usr/bin/grep -Fc 'recording_stop_handoff phase=completed' "$LOG")"
if [[ "$ACCEPTED_COUNT" != "$COMPLETED_COUNT" ]]; then
  print -u2 "Recording stop handoffs are unbalanced: accepted=$ACCEPTED_COUNT completed=$COMPLETED_COUNT log=$LOG"
  exit 1
fi

if /usr/bin/grep -Fq 'recording_finish_aborted' "$LOG"; then
  print -u2 "Installed runtime recorded an aborted recording finalization: $LOG"
  exit 1
fi

print "TypeWhaleRecordingFinalizationRuntimeCheck passed version=$VERSION build=$BUILD handoffs=$ACCEPTED_COUNT"
