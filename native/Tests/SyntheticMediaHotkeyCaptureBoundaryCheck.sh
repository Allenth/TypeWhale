#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPTURE="$ROOT/native/Sources/Presentation/Main/MainViewController+HotkeyCapture.swift"

cg_capture_block="$(
  awk '
    /func capture\(event: CGEvent, type: CGEventType\)/ { in_block=1 }
    in_block { print }
    in_block && /func capture\(event: NSEvent\)/ { exit }
  ' "$CAPTURE"
)"

ns_capture_block="$(
  awk '
    /func capture\(event: NSEvent\)/ { in_block=1 }
    in_block { print }
    in_block && /func captureModifier\(keyCode:/ { exit }
  ' "$CAPTURE"
)"

if ! grep -Fq 'SyntheticMediaKeyEvent.isTypeWhaleGenerated(event)' <<<"$cg_capture_block"; then
  echo "CGEvent hotkey capture must ignore TypeWhale-generated media controls" >&2
  exit 1
fi

if ! grep -Fq 'SyntheticMediaKeyEvent.isTypeWhaleGenerated(cgEvent)' <<<"$ns_capture_block"; then
  echo "NSEvent hotkey capture must ignore TypeWhale-generated media controls" >&2
  exit 1
fi

echo "SyntheticMediaHotkeyCaptureBoundaryCheck passed"
