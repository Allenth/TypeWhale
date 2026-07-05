#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL_LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
PREFERENCES="$ROOT/native/Sources/Presentation/Main/MainViewController+Preferences.swift"
SOURCES="$ROOT/native/Sources"

if grep -q "hasHorizontalScroller = true" "$PANEL_LAYOUT"; then
  echo "Main window settings must not use a horizontal panel scroller." >&2
  exit 1
fi

if grep -q "panelScrollView" "$PANEL_LAYOUT"; then
  echo "Main panel layout must not depend on panelScrollView." >&2
  exit 1
fi

if grep -q "scrollToConfigPanels" "$PREFERENCES"; then
  echo "Preferences must select a stable inspector tab, not scroll horizontally." >&2
  exit 1
fi

if grep -R -q "scrollToConfigPanels" "$SOURCES"; then
  echo "Source must not keep the removed horizontal settings navigation hook." >&2
  exit 1
fi

grep -q "buildInspectorTabs" "$PANEL_LAYOUT" || {
  echo "Main panel layout must expose stable inspector tabs." >&2
  exit 1
}

grep -q "func panelTitleLabel" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Main window titles must use shared typography helpers." >&2
  exit 1
}

grep -q "func inspectorGroupTitleLabel" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Inspector group headings must use shared typography helpers." >&2
  exit 1
}

grep -q "func controlRowLabel" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Control row labels must use shared typography helpers." >&2
  exit 1
}

if grep -q "controller.resetInspectorReadingPosition()" "$ROOT/native/Sources/Application/AppLifecycleCoordinator.swift"; then
  echo "Opening the main window must preserve the user's inspector scroll position." >&2
  exit 1
fi

grep -q "func inspectorGroupBox" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Inspector groups must use shared spacing surfaces, not one-off rounded boxes." >&2
  exit 1
}

grep -q "static let controlLabelWidth" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Control row labels need a shared width to stabilize long Chinese labels." >&2
  exit 1
}

if grep -q 'let header = label(title, size:' "$PANEL_LAYOUT"; then
  echo "Panel layout must not hand-code title label sizes." >&2
  exit 1
fi

echo "MainWindowLayoutBoundaryCheck passed"
