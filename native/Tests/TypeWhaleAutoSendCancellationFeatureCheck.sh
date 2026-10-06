#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-auto-send-cancel.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
  "$ROOT/native/Sources/Domain/AutoSendDomain.swift" \
  "$ROOT/native/Sources/Domain/AutoSendCountdownDomain.swift" \
  "$ROOT/native/Tests/RightMouseCountdownCancellationCheck.swift" \
  -o "$OUT/RightMouseCountdownCancellationCheck"
"$OUT/RightMouseCountdownCancellationCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Domain/AutoSendDomain.swift" \
  "$ROOT/native/Sources/Domain/AutoSendCountdownDomain.swift" \
  "$ROOT/native/Sources/Application/AutoSendCountdownCoordinator.swift" \
  "$ROOT/native/Tests/AutoSendCountdownCoordinatorCheck.swift" \
  -o "$OUT/AutoSendCountdownCoordinatorCheck"
"$OUT/AutoSendCountdownCoordinatorCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Domain/HotkeyDomain.swift" \
  "$ROOT/native/Tests/HotkeyEscapeCancellationCheck.swift" \
  -o "$OUT/HotkeyEscapeCancellationCheck"
"$OUT/HotkeyEscapeCancellationCheck"

/bin/zsh "$ROOT/native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh"
/bin/zsh "$ROOT/native/Tests/MouseShortcutExclusiveEventTapBoundaryCheck.sh"

grep -Fq 'hotkey.onRightMouse' "$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
grep -Fq 'reason: .rightMouseButton' "$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
grep -Fq 'handleRightMouseCancellation' "$ROOT/native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift"

print "TypeWhaleAutoSendCancellationFeatureCheck passed"
