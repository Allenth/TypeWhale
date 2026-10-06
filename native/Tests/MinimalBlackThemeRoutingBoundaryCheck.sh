#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MINIMAL_DIR="$ROOT/native/Sources/Presentation/MinimalBlackPreview"
PRESENTER="$MINIMAL_DIR/MinimalBlackPreviewPresenter.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

test -f "$PRESENTER"
grep -Fq 'final class MinimalBlackPreviewPresenter: PreviewPresenting' "$PRESENTER"
grep -Fq 'popup = MinimalBlackPreviewPresenter()' "$COORDINATOR"

if rg -n 'CandidatePreview|ShadowTranscriptionRuntime|FinalDeliveryUseCase|PasteCoordinator|TranscriptionProvider' "$MINIMAL_DIR"; then
  echo "MinimalBlackThemeRoutingBoundaryCheck failed: minimal-black UI crossed a forbidden boundary." >&2
  exit 1
fi

echo "MinimalBlackThemeRoutingBoundaryCheck passed"
