#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/native/Sources/Presentation/Main/ASRBenchmarkViewController.swift"
WINDOW="$ROOT/native/Sources/Presentation/Main/ASRBenchmarkWindowController.swift"
for token in 'recordOrStop' 'importAudio' 'playSample' 'runAll' 'cancelBenchmark' 'clearResults' 'temporaryHotwords'; do grep -q "$token" "$VIEW"; done
grep -q 'ASR 模型测速' "$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
! grep -Eq 'Pasteboard|RecentTranscription|SpeechInputCoordinator' "$VIEW"
test -s "$WINDOW"
echo "ASRBenchmarkUIBoundaryCheck passed"
