#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
CACHE="$ROOT/native/Sources/Application/RealtimeTranscription/ProductionRealtimePreviewDeliveryCache.swift"

test -f "$CACHE"

grep -q 'private var productionRealtimePreviewDeliveryCache = ProductionRealtimePreviewDeliveryCache()' "$COORDINATOR"
grep -q 'productionRealtimePreviewDeliveryCache.reset()' "$COORDINATOR"
grep -q 'productionRealtimePreviewDeliveryCache.consume(' "$COORDINATOR"
grep -q 'audioCoverageSeconds: request.audioCoverageSeconds' "$COORDINATOR"
grep -q 'productionRealtimePreviewDeliveryCache.complete(recordingDurationSeconds: recordingDuration)' "$COORDINATOR"
grep -q 'productionRealtimePreviewDeliveryCache.deliverySnapshot()' "$COORDINATOR"
grep -q 'prepareShadowPreviewForFinalDelivery(recordingDuration: result?.1)' "$COORDINATOR"

if rg -n 'realtimePreviewDeliverySnapshot\s*=\s*await candidateRuntime\?\.completeForDelivery\(\)' "$COORDINATOR"; then
  echo "Production delivery cache must not be read from candidatePreviewRuntime." >&2
  exit 1
fi

echo "ProductionPreviewDeliveryCacheWiringCheck passed"
