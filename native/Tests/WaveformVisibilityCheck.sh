#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UI_COMPONENTS="$ROOT/native/Sources/Presentation/Shared/UIComponents.swift"
THEME_PREVIEW="$ROOT/native/Sources/Presentation/Main/ThemePreviewTile.swift"
THEME_SNAPSHOT_FACTORY="$ROOT/native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift"
CAPSULE_VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"

grep -q "waveformStroke" "$UI_COMPONENTS" || {
  echo "Waveforms need a dedicated high-contrast stroke color in the water-ink theme." >&2
  exit 1
}

grep -q "waveformGlow" "$UI_COMPONENTS" || {
  echo "Waveforms need a subtle glow layer so thin strokes stay legible on ink panels." >&2
  exit 1
}

grep -q "waveformLiveLineWidth" "$UI_COMPONENTS" || {
  echo "Live waveforms must use an explicit readable line width token." >&2
  exit 1
}

grep -q "waveformPreviewLineWidth" "$UI_COMPONENTS" || {
  echo "Preview waveforms must use an explicit readable line width token." >&2
  exit 1
}

grep -q "CapsuleThemeSnapshotFactory.makeSnapshot" "$THEME_PREVIEW" || {
  echo "Theme preview must use production-backed snapshots." >&2
  exit 1
}

grep -q "RecordingPanel()" "$THEME_SNAPSHOT_FACTORY" || {
  echo "Classic theme snapshot must reuse the production recording panel waveform." >&2
  exit 1
}

grep -q "UITheme.waveformStroke" "$CAPSULE_VIEW" || {
  echo "Recording capsule waveform must use the high-contrast waveform stroke." >&2
  exit 1
}

echo "WaveformVisibilityCheck passed"
