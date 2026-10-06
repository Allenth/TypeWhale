#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

UI_DIRS=(
  "$ROOT/native/Sources/Presentation/Capsule"
  "$ROOT/native/Sources/Presentation/ShadowPreview"
)

if rg -n 'CandidateTranscriptQualityGate|SenseVoiceBoundaryReconciler|FinalRecognitionUseCase|FinalDeliveryUseCase|cleanRecognitionText|isMeaningfulRecognitionText|tailGapMilliseconds' "${UI_DIRS[@]}"; then
  echo "RealtimeRecognitionQualityBoundaryCheck failed: preview UI must not own recognition quality or final delivery decisions." >&2
  exit 1
fi

if rg -n '体验验|设计计|公司功功能|用户体人比我了|realtime-preview-shortfall-fallback|hallucination' "${UI_DIRS[@]}"; then
  echo "RealtimeRecognitionQualityBoundaryCheck failed: preview UI must not patch known recognition-quality examples." >&2
  exit 1
fi

echo "RealtimeRecognitionQualityBoundaryCheck passed"
