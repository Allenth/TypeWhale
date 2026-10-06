#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-remote-hid-isolation.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteVoiceKeySuppressionGate.swift" \
  "$ROOT/native/Tests/RemoteVoiceKeySuppressionGateCheck.swift" \
  -o "$OUT/RemoteVoiceKeySuppressionGateCheck"
"$OUT/RemoteVoiceKeySuppressionGateCheck"

HID="$ROOT/native/Sources/Infrastructure/Remote/RemoteHIDMonitor.swift"
HOTKEY="$ROOT/native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift"

grep -Fq 'RemoteVoiceKeySuppressionRegistry.shared.observeRemoteVoiceHID' "$HID"
grep -Fq 'IOHIDValueGetTimeStamp' "$HID"
grep -Fq 'RemoteVoiceKeySuppressionRegistry.shared.reset' "$HID"
grep -Fq 'RemoteVoiceKeySuppressionRegistry.shared.decide' "$HOTKEY"
grep -Fq 'remote_voice_f5' "$HOTKEY"
if grep -Fq 'kIOHIDOptionsTypeSeizeDevice' "$HID"; then
  print -u2 "The RC003 must remain non-exclusive so its other system buttons keep working"
  exit 1
fi

print "TypeWhaleRemoteHIDIsolationFeatureCheck passed"
