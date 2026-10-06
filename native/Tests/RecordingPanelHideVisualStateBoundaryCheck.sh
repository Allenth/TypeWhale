#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL="$ROOT/native/Sources/Presentation/Capsule/RecordingPanel.swift"

hide_body="$(
  awk '
    /func hideAnimated\(\)/ { capture = 1 }
    /private func resizeAndPosition\(\)/ { capture = 0 }
    capture { print }
  ' "$PANEL"
)"

line_of() {
  local pattern="$1"
  printf '%s\n' "$hide_body" | rg -n "$pattern" | head -1 | cut -d: -f1
}

order_out_line="$(line_of 'orderOut\(nil\)')"
accent_reset_line="$(line_of 'updateAccent\(\.normal\)')"
connection_reset_line="$(line_of 'updateOpenClawConnectionStatus\(\.checking\)')"

if (( accent_reset_line <= order_out_line )); then
  echo "OpenClaw accent must remain visible until the panel is fully hidden" >&2
  exit 1
fi
if (( connection_reset_line <= order_out_line )); then
  echo "OpenClaw connection visual reset must happen after the panel is hidden" >&2
  exit 1
fi

echo "RecordingPanelHideVisualStateBoundaryCheck passed"
