#!/usr/bin/env bash
set -euo pipefail

file="native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift"

rg -q 'applicationListWidthBeforeAdvanced' "$file"
rg -q 'applicationListPane\.isHidden = true' "$file"
rg -q 'restoredApplicationDividerPosition' "$file"
rg -q 'setPosition\(restoredPosition, ofDividerAt: 1\)' "$file"

echo "ApplicationScopeAdvancedLayoutBoundaryCheck passed"
