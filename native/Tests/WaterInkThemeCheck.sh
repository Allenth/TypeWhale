#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UI_COMPONENTS="$ROOT/native/Sources/Presentation/Shared/UIComponents.swift"
MAIN_VIEW="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
PANEL_LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
CAPSULE_VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"
BUILD_NATIVE="$ROOT/native/build_native_app.sh"

grep -q "waterInk" "$UI_COMPONENTS" || {
  echo "UITheme must expose waterInk colors as the global visual system." >&2
  exit 1
}

grep -q "TypeWhaleAppIcon-yellow-pro.png" "$BUILD_NATIVE" || {
  echo "Native Pro build must use the approved yellow-whale Pro app icon source." >&2
  exit 1
}

xcrun swift "$ROOT/native/Tests/AppIconGeometryCheck.swift" \
  "$ROOT/assets/TypeWhaleAppIcon-yellow-pro.png"

grep -q "UITheme.windowOverlay" "$MAIN_VIEW" || {
  echo "Main window background overlay must come from the water-ink theme token." >&2
  exit 1
}

grep -q "UITheme.panelFill" "$PANEL_LAYOUT" || {
  echo "Main window panels must use the water-ink panel fill token." >&2
  exit 1
}

grep -q "UITheme.capsuleAccent" "$CAPSULE_VIEW" || {
  echo "Recording capsule must use the water-ink capsule accent token." >&2
  exit 1
}

if grep -q "state == .on ? UITheme.brandYellow" "$UI_COMPONENTS"; then
  echo "Switches must not keep the old yellow on-state in the water-ink UI." >&2
  exit 1
fi

echo "WaterInkThemeCheck passed"
