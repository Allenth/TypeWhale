#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"

grep -q "MainCapsuleRenderState" "$VIEW"
grep -q "MainCapsuleTextMotion" "$VIEW"
grep -q "CapsuleTextBuffer" "$VIEW"
grep -q 'private let draftStepInterval: TimeInterval = 0.05' "$VIEW"

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview'

if grep -E "$FORBIDDEN_PATTERN" "$VIEW"; then
  echo "Main capsule preview text migration must not reference delivery, cache, provider, reconciler, shadow, or candidate preview types." >&2
  exit 1
fi

echo "MainCapsulePreviewTextMigrationBoundaryCheck passed"
