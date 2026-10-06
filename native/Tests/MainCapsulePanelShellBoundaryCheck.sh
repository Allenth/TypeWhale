#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL="$ROOT/native/Sources/Presentation/Capsule/RecordingPanel.swift"
SHELL="$ROOT/native/Sources/Presentation/Capsule/MainCapsulePanelShell.swift"

test -f "$SHELL"
grep -q "MainCapsulePanelShell" "$PANEL"

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview'

if grep -E "$FORBIDDEN_PATTERN" "$PANEL" "$SHELL"; then
  echo "Main capsule panel shell must not directly reference delivery, cache, provider, reconciler, shadow, or candidate preview types." >&2
  exit 1
fi

echo "MainCapsulePanelShellBoundaryCheck passed"
