#!/usr/bin/env bash
set -euo pipefail

window_file="native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift"
row_file="native/Sources/Presentation/Main/Dialogs/ApplicationScopeApplicationRowView.swift"
view_file="native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift"

rg -q '\.resizable' "$window_file"
rg -q 'contentMinSize' "$window_file"
rg -q 'visibleFrame' "$window_file"
rg -q 'contentContainer' "$window_file"
rg -q 'windowWillClose' "$window_file"

if [[ -f "$view_file" ]]; then
  rg -q 'NSSplitView' "$view_file"
  test "$(rg -c 'NSScrollView' "$view_file")" -ge 2
  rg -q 'allowsMultipleSelection = true' "$view_file"
  rg -q 'rowHeight = 52' "$view_file"
fi

if [[ -f "$row_file" ]] && rg -n \
  'UserDefaults|SmartRewriteAutoRuleStore|AutoSendSettingsStore' "$row_file"; then
  echo "Application row must render supplied values without reading settings" >&2
  exit 1
fi

if rg -n 'FormSheetController|widthAnchor\.constraint\(equalToConstant|heightAnchor\.constraint\(equalToConstant' "$window_file"; then
  echo "ApplicationScopeWindowController must not use the fixed-size form sheet" >&2
  exit 1
fi

echo "ApplicationScopeLayoutBoundaryCheck passed"
