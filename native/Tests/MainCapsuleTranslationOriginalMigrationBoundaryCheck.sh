#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"
PROJECTION="$ROOT/native/Sources/Presentation/Capsule/MainCapsuleLegacyStatusProjection.swift"
RENDER="$ROOT/native/Sources/Presentation/Capsule/MainCapsuleRenderState.swift"

test -f "$PROJECTION"
grep -q "MainCapsuleLegacyStatusProjection" "$VIEW"
grep -q "statusTextOverride" "$RENDER"
grep -q "renderState.statusText.draw" "$VIEW"

if grep -q "state.draw(in: stateRect" "$VIEW"; then
  echo "RecordingCapsuleView must draw status text from MainCapsuleRenderState, not directly from legacy state." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview'

if grep -E "$FORBIDDEN_PATTERN" "$VIEW" "$PROJECTION" "$RENDER"; then
  echo "Main capsule translation/original migration must not reference delivery, cache, provider, reconciler, shadow, or candidate preview types." >&2
  exit 1
fi

echo "MainCapsuleTranslationOriginalMigrationBoundaryCheck passed"
