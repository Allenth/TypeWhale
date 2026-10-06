#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"

grep -Fq 'let correctedPreviewExperiment = BrandSwitch()' "$MAIN"
grep -Fq 'let longFormIncrementalOutputExperiment = BrandSwitch()' "$MAIN"
grep -Fq 'optionRow("重叠矫正", correctedPreviewExperiment, showsLeader: true)' "$LAYOUT"
! grep -Fq '长录音增量输出（实验）' "$LAYOUT"
grep -Fq 'correctedPreviewExperiment.setAccessibilityLabel' "$CONFIG"
grep -Fq 'longFormIncrementalOutputExperiment.setAccessibilityLabel' "$CONFIG"
grep -Fq 'normalizeExperimentalPreviewSettings' "$ACTIONS"
grep -Fq 'supportsSenseVoice' "$ACTIONS"
grep -Fq 'longFormIncrementalOutputExperiment.state == .off' "$ACTIONS"
grep -Fq 'restoreSavedPreference' "$ACTIONS"
grep -Fq 'correctedPreviewEnabled: correctedPreviewExperiment.state == .on' "$ACTIONS"
grep -Fq 'longFormIncrementalOutputEnabled: false' "$ACTIONS"

python3 - <<'PY'
from pathlib import Path

source = Path("native/Sources/Presentation/Main/MainViewController+PanelLayout.swift").read_text()
body = source[source.index("    private func buildRecordingPreviewSettingsContent") : source.index("\n    private func buildPrimaryMicrophoneContent")]
realtime = body.index('optionRow("胶囊实时预览", realtime)')
correction = body.index('optionRow("重叠矫正", correctedPreviewExperiment, showsLeader: true)')
diagnostics = body.index('subSectionView("诊断工具（实验）"')
if not (realtime < correction < diagnostics):
    raise SystemExit("重叠矫正必须紧跟实时预览，并位于诊断工具之前")
if body.count('optionRow("重叠矫正", correctedPreviewExperiment, showsLeader: true)') != 1:
    raise SystemExit("重叠矫正入口必须且只能出现一次")

preferences = Path("native/Sources/Presentation/Main/MainViewController+Preferences.swift").read_text()
if "showsLeader: Bool = false" not in preferences or "dottedLeaderView()" not in preferences:
    raise SystemExit("重叠矫正行必须使用可选虚线引导，不得改变所有设置行")

components = Path("native/Sources/Presentation/Shared/UIComponents.swift").read_text()
if "lineDashPattern" not in components or "func dottedLeaderView()" not in components:
    raise SystemExit("缺少低对比度虚线引导组件")

actions = Path("native/Sources/Presentation/Main/MainViewController+Actions.swift").read_text()
getter = actions[actions.index("    var experimentalPreviewSettings:") : actions.index("\n    var previewTheme:")]
if "correctedPreviewEnabled: correctedPreviewExperiment.state == .on" not in getter:
    raise SystemExit("录音运行时必须读取重叠矫正开关，不能强制关闭")
if "correctedPreviewEnabled: false" in getter:
    raise SystemExit("录音运行时仍在强制关闭重叠矫正")
PY

echo "ExperimentalPreviewSettingsBoundaryCheck passed"
