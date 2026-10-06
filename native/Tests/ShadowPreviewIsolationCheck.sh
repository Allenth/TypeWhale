#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHADOW="$ROOT/native/Sources/Presentation/ShadowPreview"
SETTINGS="$ROOT/native/Sources/Infrastructure/Settings/ShadowPreviewSettings.swift"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
PREVIEW_PROTOCOL="$ROOT/native/Sources/Presentation/Capsule/PreviewPresenting.swift"

for forbidden in finishRecording activeSession PasteCoordinator RecordingTask onVoiceProbe containsSpeech SmartInput OpenClaw; do
  if rg -n "$forbidden" "$SHADOW" >/dev/null; then
    echo "Shadow Preview must not reference $forbidden" >&2
    exit 1
  fi
done

grep -Fq 'static let defaultValue = ShadowPreviewSettings(isEnabled: false)' "$SETTINGS"
grep -Fq 'let shadowPreviewExperiment = BrandSwitch()' "$MAIN"
grep -Fq '旁路预览（诊断）' "$LAYOUT"
grep -Fq '诊断工具（实验）' "$LAYOUT"
grep -Fq '诊断用：在主胶囊旁显示旁路结果；不参与最终识别和粘贴。' "$LAYOUT"
grep -Fq 'saveShadowPreviewSettings' "$ACTIONS"
grep -Fq 'subscriptionTask?.cancel()' "$SHADOW/ShadowPreviewCoordinator.swift"
grep -Fq 'presenter.hideImmediately()' "$SHADOW/ShadowPreviewCoordinator.swift"
grep -Fq 'beginShadowPreview(taskID:' "$SPEECH"
grep -Fq 'publishShadowPreview(' "$SPEECH"
grep -Fq 'endShadowPreview(' "$SPEECH"
grep -Fq 'var presentationFrame: CGRect?' "$PREVIEW_PROTOCOL"

# 旁路只允许在生产 UI 更新之后收到快照副本。
python3 - "$SPEECH" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
old_capsule_marker = "popup.updateDraft(snapshot)"
shadow_marker = "publishShadowPreview(productSnapshot, taskID:"
cursor = 0
matches = 0
while True:
    old_index = source.find(old_capsule_marker, cursor)
    if old_index < 0:
        break
    shadow_index = source.find(shadow_marker, old_index)
    if shadow_index >= 0:
        matches += 1
        cursor = shadow_index + len(shadow_marker)
    else:
        cursor = old_index + len(old_capsule_marker)
if matches < 2:
    raise SystemExit("both production preview paths must publish to shadow after updating the old capsule")
PY

echo "ShadowPreviewIsolationCheck passed"
