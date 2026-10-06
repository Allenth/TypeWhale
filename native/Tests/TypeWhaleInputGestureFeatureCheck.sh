#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-input-gesture.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
  "$ROOT/native/Sources/Domain/Hotkey/HotkeyPressGesturePolicy.swift" \
  "$ROOT/native/Tests/HotkeyPressGesturePolicyCheck.swift" \
  -o "$OUT/HotkeyPressGesturePolicyCheck"
"$OUT/HotkeyPressGesturePolicyCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteVoiceControlPolicy.swift" \
  "$ROOT/native/Tests/RemoteVoiceControlPolicyCheck.swift" \
  -o "$OUT/RemoteVoiceControlPolicyCheck"
"$OUT/RemoteVoiceControlPolicyCheck"

COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
HOTKEY="$ROOT/native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift"
REMOTE="$ROOT/native/Sources/Infrastructure/Remote/RemoteBluetoothController.swift"

grep -Fq 'hotkey.onTimedDown' "$COORDINATOR"
grep -Fq 'hotkey.onTimedUp' "$COORDINATOR"
grep -Fq 'HotkeyPressGesturePolicy' "$COORDINATOR"
grep -Fq 'hotkey_gesture phase=classified' "$COORDINATOR"
grep -Fq 'event_uptime_ns=' "$HOTKEY"
grep -Fq 'RemoteVoiceControlPolicy' "$REMOTE"
grep -Fq 'remote_voice_control' "$REMOTE"

print "TypeWhaleInputGestureFeatureCheck passed"
