#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL="$ROOT/native/Sources/Presentation/Capsule/RecordingPanel.swift"

if ! grep -q "MainCapsuleContextPresentation" "$PANEL"; then
  echo "RecordingPanel must use MainCapsuleContextPresentation for top context values." >&2
  exit 1
fi

if ! grep -q "contextState = MainCapsuleContext" "$PANEL"; then
  echo "RecordingPanel must keep a MainCapsuleContext state for top info bar updates." >&2
  exit 1
fi

if grep -q 'let rawName = (appName?.isEmpty == false)' "$PANEL"; then
  echo "App name fallback must move out of RecordingPanel imperative label assignment." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview|SmartRewriteEngine|SenseVoice|VAD'
if grep -E "$FORBIDDEN_PATTERN" "$PANEL" >/dev/null; then
  echo "Context display migration must not touch delivery/provider/shadow/candidate/rewrite/asr paths." >&2
  exit 1
fi

echo "MainCapsuleContextMigrationBoundaryCheck passed"
