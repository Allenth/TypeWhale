#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MINIMAL_DIR="$ROOT/native/Sources/Presentation/MinimalBlackPreview"
PRESENTER="$MINIMAL_DIR/MinimalBlackPreviewPresenter.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

test -d "$MINIMAL_DIR"
test -f "$PRESENTER"
grep -Fq 'final class MinimalBlackPreviewPresenter: PreviewPresenting' "$PRESENTER"
grep -Fq 'func updateDraft(_ snapshot: PreviewDisplaySnapshot)' "$PRESENTER"
grep -Fq 'popup = MinimalBlackPreviewPresenter()' "$COORDINATOR"
grep -Fq 'productionPreviewTextCoordinator.replaceSink(popup)' "$COORDINATOR"

if rg -n 'AsyncStream|PreviewViewState|ShadowTranscriptionRuntime|ShadowPreview|TranscriptionProvider|Reconciler|FinalDelivery|PasteCoordinator' "$MINIMAL_DIR"; then
  echo "MinimalBlackProductionBoundaryCheck failed: minimal-black presentation owns non-presentation state." >&2
  exit 1
fi

if rg -n 'CandidatePreview(View|Presenter|Coordinator)|ThreeCapsuleLayout' "$ROOT/native/Sources"; then
  echo "MinimalBlackProductionBoundaryCheck failed: retired candidate runtime or layout returned." >&2
  exit 1
fi

if rg -n 'MainCapsuleVisualStyle' "$ROOT/native/Sources" \
  || rg -n -F 'RecordingPanel(visualStyle:' "$ROOT/native/Sources"; then
  echo "MinimalBlackProductionBoundaryCheck failed: rejected skin implementation returned." >&2
  exit 1
fi

echo "MinimalBlackProductionBoundaryCheck passed"
