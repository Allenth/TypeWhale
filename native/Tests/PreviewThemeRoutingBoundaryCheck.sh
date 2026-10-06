#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETTINGS="$ROOT/native/Sources/Infrastructure/Settings/AppSettings.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
TILE="$ROOT/native/Sources/Presentation/Main/ThemePreviewTile.swift"
SNAPSHOT_FACTORY="$ROOT/native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift"

grep -Fq 'case minimalBlack' "$SETTINGS"
grep -Fq 'popup = MinimalBlackPreviewPresenter()' "$COORDINATOR"
grep -Fq 'productionPreviewTextCoordinator.replaceSink(popup)' "$COORDINATOR"
grep -Fq 'activePreviewTheme = theme' "$COORDINATOR"
grep -Fq 'weak var previewThemeMinimalBlackTile: ThemePreviewTile?' "$MAIN"
grep -Fq 'ThemePreviewTile(kind: .minimalBlack, title: "简洁黑色")' "$LAYOUT"
grep -Fq 'previewThemeMinimalBlackTile?.isSelected = current == .minimalBlack' "$LAYOUT"
grep -Fq 'CapsuleThemeSnapshotFactory.makeSnapshot(for: kind)' "$TILE"
grep -Fq 'RecordingPanel()' "$SNAPSHOT_FACTORY"
grep -Fq 'NotchPreviewPresenter()' "$SNAPSHOT_FACTORY"
grep -Fq 'MinimalBlackPreviewPresenter()' "$SNAPSHOT_FACTORY"
if grep -Fq 'drawClassic(in:' "$TILE"; then
  echo "Theme tiles must snapshot production presenters instead of abstract drawings" >&2
  exit 1
fi

python3 - "$COORDINATOR" "$TILE" <<'PY'
from pathlib import Path
import sys

coordinator = Path(sys.argv[1]).read_text()
tile = Path(sys.argv[2]).read_text()

recording_start = coordinator[coordinator.index("workflowState.startRecording(taskID: taskID)"):]
theme_call = 'applyPreviewTheme(purpose == .ideaPill || purpose == .openClawChat ? .classic : controller.previewTheme)'
if theme_call not in recording_start:
    raise SystemExit("idea pill and OpenClaw must keep classic theme")

if '"候选"' in tile or "等待候选结果" in tile:
    raise SystemExit("minimal black theme must not render candidate labeling")
PY

echo "PreviewThemeRoutingBoundaryCheck passed"
