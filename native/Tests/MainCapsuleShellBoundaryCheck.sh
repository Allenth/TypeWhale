#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"
SHELL="$ROOT/native/Sources/Presentation/Capsule/MainCapsuleShell.swift"

test -f "$SHELL"

grep -q "MainCapsuleShell" "$VIEW"

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview'

if grep -E "$FORBIDDEN_PATTERN" "$VIEW" "$SHELL"; then
  echo "Main capsule shell/view must not directly reference data delivery, provider, reconciler, shadow, or candidate preview types." >&2
  exit 1
fi

echo "MainCapsuleShellBoundaryCheck passed"
