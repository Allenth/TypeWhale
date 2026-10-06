#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"

if ! grep -q "drawInnerGlowIfNeeded(in: capsuleRect, radius: radius, renderState: renderState)" "$VIEW"; then
  echo "RecordingCapsuleView must pass MainCapsuleRenderState into purpose inner glow drawing." >&2
  exit 1
fi

if grep -q "guard innerGlow != \\.none else { return }" "$VIEW"; then
  echo "Purpose inner glow visibility must be decided from render state, not directly from innerGlow." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview|BacklogWriter'
if grep -E "$FORBIDDEN_PATTERN" "$VIEW" >/dev/null; then
  echo "Idea pill display migration must not touch delivery/provider/shadow/candidate/save paths." >&2
  exit 1
fi

echo "MainCapsuleIdeaPillMigrationBoundaryCheck passed"
