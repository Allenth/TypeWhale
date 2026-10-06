#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHEET="$ROOT/native/Sources/Presentation/Main/TTSMyVoiceRecordingViewController.swift"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift"
VIEW="$ROOT/native/Sources/Presentation/Main/TTSReadingLabView.swift"

grep -Fq 'TTSLabPersonalVoiceStore.referenceText' "$SHEET"
grep -Fq '0.8' "$SHEET"
grep -Fq 'elapsed >= 2.70' "$SHEET"
grep -Fq '读出下面的句子' "$SHEET"
grep -Fq 'PermissionDiagnosticsProvider.requestMicrophone' "$SHEET"
grep -Fq '录音和克隆参考仅保存在这台 Mac，不会上传。' "$SHEET"
grep -Fq 'store.prepareCandidate' "$SHEET"
grep -Fq 'clonePreviewSucceeded' "$SHEET"
grep -Fq 'recordMyVoiceButton' "$VIEW"
grep -Fq 'presentMyVoiceRecordingSheet' "$MAIN"
grep -Fq 'installPersonalVoiceInReadingLab' "$MAIN"
echo "TTSMyVoiceRecordingSourceCheck passed"
