#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PROVIDER_FILES=(
  "$ROOT/native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift"
  "$ROOT/native/Sources/Domain/RealtimeTranscription/TranscriptionProviderEventContract.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/OnlineTranscriptionProvider.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift"
)

if rg -n 'RecordingCapsuleView|ShadowPreviewView|FinalDeliveryUseCase|PasteCoordinator' "${PROVIDER_FILES[@]}"; then
  echo "TranscriptionProviderBoundaryCheck failed: Provider files must not reference capsule UI or final delivery." >&2
  exit 1
fi

if rg -n 'SenseVoiceSnapshotProvider|MiMoSnapshotProvider|OnlineTranscriptionProvider|DoubaoStreamingTransport|TranscriptionProviderEventContract' \
  "$ROOT/native/Sources/Presentation/Capsule" \
  "$ROOT/native/Sources/Presentation/ShadowPreview"; then
  echo "TranscriptionProviderBoundaryCheck failed: Preview UI must not reference concrete Provider implementations." >&2
  exit 1
fi

echo "TranscriptionProviderBoundaryCheck passed"
