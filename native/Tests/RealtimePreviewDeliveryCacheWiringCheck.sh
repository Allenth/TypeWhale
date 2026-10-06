#!/usr/bin/env bash
set -euo pipefail

RUNTIME="native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift"

grep -Fq 'private var realtimePreviewDeliveryCache = RealtimePreviewDeliveryCache()' "$RUNTIME"
grep -Fq 'realtimePreviewDeliveryCache.deliverySnapshot()' "$RUNTIME"
grep -Fq 'realtimePreviewDeliveryCache.consume(completeTranscript)' "$RUNTIME"
grep -Fq 'realtimePreviewDeliveryCache.complete()' "$RUNTIME"

if rg -n 'legacyDeliveryCache|LegacyRealtimePreviewDeliveryCache\\(\\)' "$RUNTIME"; then
    echo "ShadowTranscriptionRuntime must use the neutral RealtimePreviewDeliveryCache field" >&2
    exit 1
fi

if rg -n 'FinalDeliveryUseCase|FinalRecognitionUseCase|PasteCoordinator|RecordingCapsuleView|CandidatePreviewView|ShadowPreviewView' "$RUNTIME"; then
    echo "Realtime preview delivery cache wiring must not touch UI or final delivery policy" >&2
    exit 1
fi

echo "RealtimePreviewDeliveryCacheWiringCheck passed"
