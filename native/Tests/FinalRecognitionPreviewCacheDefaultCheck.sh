#!/usr/bin/env bash
set -euo pipefail

if ! grep -q 'var reRecognizeWholeRecordingAfterStop: Bool' native/Sources/Infrastructure/Settings/AppSettings.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: settings flag missing' >&2
  exit 1
fi

if ! grep -q 'UserDefaults.standard.bool(forKey: reRecognizeWholeRecordingAfterStopKey)' native/Sources/Infrastructure/Settings/AppSettings.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: setting must default to false when absent' >&2
  exit 1
fi

if ! grep -q 'optionRow("停止后重新识别整段录音", reRecognizeWholeRecordingAfterStop)' native/Sources/Presentation/Main/MainViewController+PanelLayout.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: user-facing switch missing' >&2
  exit 1
fi

if ! grep -q 'reRecognizeWholeRecordingAfterStop: task.reRecognizeWholeRecordingAfterStop' native/Sources/Application/SpeechInputCoordinator.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: final recognition does not use the recording-scoped setting' >&2
  exit 1
fi

if ! grep -q 'completeRealtimeCacheEngine: String = "realtime-preview-delivery-cache"' native/Sources/Application/FinalRecognitionUseCase.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: complete realtime cache source is missing' >&2
  exit 1
fi

if ! grep -q 'engine: request.completeRealtimeCacheEngine' native/Sources/Application/FinalRecognitionUseCase.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: delivery cache engine must be passed through' >&2
  exit 1
fi

if ! grep -q 'FinalRecognitionAuthorityPolicy.action' native/Sources/Application/FinalRecognitionUseCase.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: selected-backend authority policy is missing' >&2
  exit 1
fi

if ! grep -q 'backend: request.configuration.backend' native/Sources/Application/FinalRecognitionUseCase.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: final authority does not use selected backend' >&2
  exit 1
fi

if grep -q 'guard request.reRecognizeWholeRecordingAfterStop else' native/Sources/Application/FinalRecognitionUseCase.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: switch-off path must not suppress selected non-SenseVoice backend' >&2
  exit 1
fi

if ! grep -q 'realtime_preview_delivery_cache' native/Sources/Application/SpeechInputCoordinator.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: final result diagnostics must expose realtime delivery cache source' >&2
  exit 1
fi

if ! grep -q 'completeRealtimeCacheText:' native/Sources/Application/FinalDeliveryUseCase.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: final delivery does not pass the complete cache into recognition policy' >&2
  exit 1
fi

if ! grep -q '选择其他识别模型时，停止录音后会自动运行所选模型' native/Sources/Presentation/Main/MainViewController+Configuration.swift; then
  echo 'FinalRecognitionPreviewCacheDefaultCheck failed: setting explanation must describe selected-model final authority' >&2
  exit 1
fi

echo 'FinalRecognitionPreviewCacheDefaultCheck passed'
