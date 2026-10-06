#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
ACTIONS="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+Actions.swift"
MAIN="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController.swift"
COORDINATOR="$ROOT_DIR/native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'case .funASRNano: return "Fun-ASR Nano"' "$ROOT_DIR/native/Sources/Domain/ASRDomain.swift"
grep -Fq '安装运行环境' "$ACTIONS"
grep -Fq '实时预览继续使用 SenseVoice' "$ACTIONS"
grep -Fq 'asrBackendMode.setAccessibilityLabel("识别模型")' "$CONFIG"
grep -Fq 'let capsulePreviewEnabled = controller.realtimePreviewEnabled' "$COORDINATOR"
grep -Fq 'let realtimeDataEnabled = true' "$COORDINATOR"
grep -Fq 'realtimeEnabled: realtimeDataEnabled' "$COORDINATOR"
grep -Fq 'let effectiveASRBackend = isASRBackendReadyForSelection(requestedASRBackend)' "$ACTIONS"
grep -Fq 'asrBackend: previousASRBackend' "$ACTIONS"
grep -Fq 'settings.asrBackend = backend' "$ACTIONS"
grep -Fq 'scheduledASRBackendChangeDelay: TimeInterval = 3.5' "$MAIN"
grep -Fq 'DispatchQueue.main.asyncAfter(deadline: .now() + scheduledASRBackendChangeDelay' "$ACTIONS"
grep -Fq 'pendingASRBackendChangeWorkItem?.cancel()' "$ACTIONS"
grep -Fq 'case .installing(let message)' "$ACTIONS"
grep -Fq 'case .failed(let message)' "$ACTIONS"
grep -Fq 'updateFunASRRuntimeState' "$COORDINATOR"
if grep -Fq 'resolvedBackend == .qwen3ASR' "$COORDINATOR"; then
  echo "Legacy Qwen3-ASR preview branch remains" >&2
  exit 1
fi

echo "FunASRBackendUIBoundaryCheck passed"
