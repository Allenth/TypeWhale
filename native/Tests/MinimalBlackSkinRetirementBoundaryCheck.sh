#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPSULE_DIR="$ROOT/native/Sources/Presentation/Capsule"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

test ! -f "$CAPSULE_DIR/MainCapsuleVisualStyle.swift"
test ! -f "$ROOT/native/Tests/MainCapsuleVisualStyleCheck.swift"

if rg -n 'MainCapsuleVisualStyle|visualStyle' \
  "$CAPSULE_DIR/RecordingPanel.swift" \
  "$CAPSULE_DIR/RecordingCapsuleView.swift"; then
  echo "MinimalBlackSkinRetirementBoundaryCheck failed: classic capsule still owns theme skin branches." >&2
  exit 1
fi

if rg -n -F 'RecordingPanel(visualStyle:' "$ROOT/native/Sources"; then
  echo "MinimalBlackSkinRetirementBoundaryCheck failed: styled RecordingPanel construction remains." >&2
  exit 1
fi

grep -Fq 'popup = RecordingPanel()' "$COORDINATOR"
grep -Fq 'popup = MinimalBlackPreviewPresenter()' "$COORDINATOR"

echo "MinimalBlackSkinRetirementBoundaryCheck passed"
