#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"

grep -Fq 'static let maxRecordingSeconds: TimeInterval = 300' "$COORDINATOR"
! grep -Fq 'static let maxRecordingSeconds: TimeInterval = 120' "$COORDINATOR"
! grep -Fq 'longFormMaxRecordingSeconds' "$COORDINATOR"
! grep -Fq 'let longFormEnabled' "$COORDINATOR"
grep -Fq 'let maximum = Timing.maxRecordingSeconds' "$COORDINATOR"
grep -Fq 'let minutes = Int((seconds / 60).rounded())' "$COORDINATOR"
grep -Fq 'finishRecording(reason: "max_duration")' "$COORDINATOR"
grep -Fq 'correctedPreviewEnabled: correctedPreviewExperiment.state == .on' "$ACTIONS"
grep -Fq 'longFormIncrementalOutputEnabled: false' "$ACTIONS"
grep -Fq 'optionRow("重叠矫正", correctedPreviewExperiment, showsLeader: true)' "$LAYOUT"
! grep -Fq 'optionRow("长录音增量输出（实验）"' "$LAYOUT"

echo "FiveMinuteRecordingLimitBoundaryCheck passed"
