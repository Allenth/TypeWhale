#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"

HOTKEYS_BLOCK="$(awk '
    /private func buildHotkeysPanelContent\(\)/ { in_hotkeys = 1 }
    in_hotkeys && /private func buildOpenClawPanelContent\(\)/ { exit }
    in_hotkeys { print }
' "$PANEL")"

OPENCLAW_BLOCK="$(awk '
    /private func buildOpenClawPanelContent\(\)/ { in_openclaw = 1 }
    in_openclaw && /private func configureOpenClawTextField/ { exit }
    in_openclaw { print }
' "$PANEL")"

if ! grep -q 'openClawHotkeyPanelCaptureButton' <<< "$HOTKEYS_BLOCK"; then
  echo "OpenClaw activation key must be configurable from the Hotkeys tab like the other shortcuts." >&2
  exit 1
fi

if grep -q 'openClawHotkeyCaptureButton' <<< "$HOTKEYS_BLOCK"; then
  echo "The Hotkeys tab must not reuse the OpenClaw tab button; each tab needs its own control instance." >&2
  exit 1
fi

if ! grep -q 'openClawHotkeyCaptureButton' <<< "$OPENCLAW_BLOCK"; then
  echo "The OpenClaw tab must keep its own activation-key control." >&2
  exit 1
fi

if ! grep -q 'beginOpenClawHotkeyCapture(_:)' "$PANEL"; then
  echo "OpenClaw shortcut capture must route through the clicked sender, matching the visible button." >&2
  exit 1
fi

echo "OpenClawHotkeysPanelSourceCheck passed"
