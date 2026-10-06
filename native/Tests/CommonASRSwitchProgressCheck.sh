#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+Layout.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
SELECTOR="$ROOT/native/Sources/Presentation/Main/ASRBackendSegmentedSelector.swift"
PROVIDER="$ROOT/native/Sources/Application/ProviderAwareFinalASR.swift"

grep -Fq 'let asrSwitchProgress = NSProgressIndicator()' "$MAIN"
grep -Fq 'let asrSwitchProgressLabel' "$MAIN"
grep -Fq 'asrBackendMode' "$LAYOUT"
grep -Fq 'asrSwitchProgress' "$LAYOUT"
grep -Fq 'beginASRBackendSwitchProgress' "$ACTIONS"
grep -Fq 'showASRBackendWarming' "$ACTIONS"
grep -Fq 'completeASRBackendSwitch' "$ACTIONS"
grep -Fq 'failASRBackendSwitch' "$ACTIONS"
grep -Fq 'pendingASRBackendChangeWorkItem?.cancel()' "$ACTIONS"
grep -Fq 'activeASRBackend' "$ACTIONS"
grep -Fq 'onASRBackendChange(backend) { [weak self] result in' "$ACTIONS"
grep -Fq 'self.asr.warmUp(backend: backend)' "$COORDINATOR"
grep -Fq 'completion(.success(()))' "$COORDINATOR"
grep -Fq 'ASRButtonFlowLayout.layout' "$SELECTOR"
grep -Fq 'override var intrinsicContentSize: NSSize' "$SELECTOR"
grep -Fq 'invalidateIntrinsicContentSize()' "$SELECTOR"
grep -Fq 'max(110, button.fittingSize.width)' "$SELECTOR"
if grep -Fq 'asrBackendMode.heightAnchor.constraint(equalToConstant: 40)' "$LAYOUT"; then
  echo "ASR selector must derive height from wrapped rows" >&2
  exit 1
fi
grep -Fq 'private func productionHotwords() -> [String]' "$PROVIDER"
grep -Fq 'Array(hotwords().prefix(64))' "$PROVIDER"

echo "CommonASRSwitchProgressCheck passed"
