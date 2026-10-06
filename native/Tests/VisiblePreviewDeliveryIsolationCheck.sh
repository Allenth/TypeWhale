#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

if rg -n 'realtime-preview-visible-cache' \
  native/Sources/Application/FinalDeliveryUseCase.swift \
  native/Sources/Application/FinalRecognitionUseCase.swift; then
  echo "visible preview still has final delivery authority" >&2
  exit 1
fi

if rg -n 'PreviewDisplaySnapshot' \
  native/Sources/Application/RealtimeTranscription/RealtimePreviewDeliveryCache.swift \
  native/Sources/Application/RealtimeTranscription/ProductionRealtimePreviewDeliveryCache.swift; then
  echo "delivery cache still consumes a UI projection type" >&2
  exit 1
fi

echo "VisiblePreviewDeliveryIsolationCheck passed"
