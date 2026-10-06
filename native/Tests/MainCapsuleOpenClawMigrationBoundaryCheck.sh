#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"

if ! grep -q "drawOpenClawBadgeIfNeeded(in: capsuleRect, renderState: renderState)" "$VIEW"; then
  echo "RecordingCapsuleView must pass MainCapsuleRenderState into OpenClaw badge drawing." >&2
  exit 1
fi

if grep -q "guard innerGlow == \\.openClaw else { return }" "$VIEW"; then
  echo "OpenClaw badge visibility must be decided from render state, not directly from innerGlow." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview|OpenClawReplyPresenter'
if grep -E "$FORBIDDEN_PATTERN" "$VIEW" >/dev/null; then
  echo "OpenClaw display migration must not touch delivery/provider/shadow/candidate/reply paths." >&2
  exit 1
fi

echo "MainCapsuleOpenClawMigrationBoundaryCheck passed"
