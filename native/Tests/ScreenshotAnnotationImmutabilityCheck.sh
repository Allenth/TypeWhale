#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCREENSHOT="$ROOT/native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift"

if grep -q "moveMarkup" "$SCREENSHOT"; then
  echo "Screenshot annotations must be create-only; existing markups cannot be dragged or moved" >&2
  exit 1
fi

if grep -q "markupIndex(at:" "$SCREENSHOT"; then
  echo "Screenshot annotations must not hit-test existing markups for selection or movement" >&2
  exit 1
fi

if grep -q "drawSelectionOutline" "$SCREENSHOT" || grep -q "setLineDash" "$SCREENSHOT"; then
  echo "Screenshot annotations must not draw the blue dashed selection outline" >&2
  exit 1
fi

if ! grep -q "case \\.redo" "$ROOT/native/Sources/Presentation/Screenshot/ScreenshotSessionState.swift"; then
  echo "Screenshot toolbar commands must include redo / 前进" >&2
  exit 1
fi

echo "ScreenshotAnnotationImmutabilityCheck passed"
