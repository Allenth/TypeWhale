#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"
MOTION="$ROOT/native/Sources/Presentation/Capsule/MainCapsuleWaveformMotion.swift"
RENDER="$ROOT/native/Sources/Presentation/Capsule/MainCapsuleRenderState.swift"

test -f "$MOTION"
grep -q "MainCapsuleWaveformMotion" "$VIEW"
grep -q "waveformBands" "$RENDER"

if grep -q "private var smoothedBands = WaveformBands" "$VIEW"; then
  echo "RecordingCapsuleView must not own the old WaveformBands smoothing state after Task 6B." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview'

if grep -E "$FORBIDDEN_PATTERN" "$VIEW" "$MOTION" "$RENDER"; then
  echo "Main capsule waveform migration must not reference delivery, cache, provider, reconciler, shadow, or candidate preview types." >&2
  exit 1
fi

echo "MainCapsuleWaveformMigrationBoundaryCheck passed"
