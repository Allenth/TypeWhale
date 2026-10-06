#!/usr/bin/env bash
set -euo pipefail

FINAL="native/Sources/Application/FinalDeliveryUseCase.swift"
COORDINATOR="native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'realtimePreviewDeliverySnapshot:' "$FINAL"
grep -Fq 'realtimePreviewDeliverySnapshot:' "$COORDINATOR"

if rg -n 'legacyCandidateSnapshot|legacyCandidate' "$FINAL" "$COORDINATOR"; then
    echo "Final delivery input naming must refer to realtime preview delivery cache, not legacy candidate" >&2
    exit 1
fi

if ! grep -Fq 'shadowRuntimeSnapshot:' "$FINAL"; then
    echo "Shadow runtime diagnostic input must remain explicit" >&2
    exit 1
fi

echo "FinalDeliveryNamingBoundaryCheck passed"
