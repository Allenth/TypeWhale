#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FACTORY="$ROOT/native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift"
TILE="$ROOT/native/Sources/Presentation/Main/ThemePreviewTile.swift"

test -f "$FACTORY" || {
  echo "Production-backed theme snapshot factory is missing" >&2
  exit 1
}

grep -Fq 'RecordingPanel()' "$FACTORY"
grep -Fq 'NotchPreviewPresenter()' "$FACTORY"
grep -Fq 'MinimalBlackPreviewPresenter()' "$FACTORY"
grep -Fq 'CapsuleThemeSnapshotFactory.makeSnapshot' "$TILE"
grep -Fq 'func makeThemePreviewSnapshot' "$ROOT/native/Sources/Presentation/Capsule/RecordingPanel.swift"
grep -Fq 'func makeThemePreviewSnapshot' "$ROOT/native/Sources/Presentation/Notch/NotchPreviewPresenter.swift"
grep -Fq 'func makeThemePreviewSnapshot' "$ROOT/native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift"

test ! -e "$ROOT/native/Helpers/CapsuleThemePreviewCapture.swift" || {
  echo "Rejected hand-drawn theme capture helper must be removed" >&2
  exit 1
}
test ! -d "$ROOT/native/Resources/ThemePreviews" || {
  echo "Rejected hand-drawn theme PNG assets must be removed" >&2
  exit 1
}

echo "CapsuleThemeProductionSnapshotBoundaryCheck passed"
