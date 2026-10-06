#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
TEXT_COORDINATOR="$ROOT/native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
SETTINGS="$ROOT/native/Sources/Infrastructure/Settings/ExperimentalPreviewSettings.swift"

grep -Fq 'let capsulePreviewEnabled = controller.realtimePreviewEnabled' "$COORDINATOR"
grep -Fq 'let realtimeDataEnabled = true' "$COORDINATOR"
grep -Fq 'realtimeEnabled: realtimeDataEnabled' "$COORDINATOR"
grep -Fq 'controller.updateRealtimeDraft("正在等待第一段实时文本…")' "$COORDINATOR"
grep -Fq 'popup.show(state: "录音中", draft: "")' "$COORDINATOR"
grep -Fq 'productionPreviewTextCoordinator.begin(' "$COORDINATOR"
grep -Fq 'deliversText: capsulePreviewEnabled' "$COORDINATOR"
grep -Fq 'func begin(states: AsyncStream<PreviewViewState>, deliversText: Bool)' "$TEXT_COORDINATOR"

python3 - <<'PY'
from pathlib import Path

source = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()
start = source[source.index("        let capsulePreviewEnabled = controller.realtimePreviewEnabled"):source.index("        beginProductionPreview(taskID: taskID, deliversText: capsulePreviewEnabled)")]
if "popup.hideAnimated()" in start:
    raise SystemExit("关闭实时文字不能隐藏整个胶囊")
PY

! grep -Fq 'baseRealtimeEnabled:' "$SETTINGS"
! grep -Fq 'baseRealtimeEnabled:' "$ACTIONS"
! grep -Fq 'correctedPreviewExperiment.isEnabled = supportsSenseVoice' "$ACTIONS" \
    || ! grep -A3 -F 'correctedPreviewExperiment.isEnabled = supportsSenseVoice' "$ACTIONS" \
        | grep -Fq 'realtime.state == .on'
! grep -A2 -F '@objc func saveExperimentalPreviewSettings()' "$ACTIONS" \
    | grep -Fq 'realtime.state = .on'

echo "CapsulePreviewIndependenceBoundaryCheck passed"
