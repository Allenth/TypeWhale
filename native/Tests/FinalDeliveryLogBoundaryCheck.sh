#!/usr/bin/env bash
set -euo pipefail

FINAL="native/Sources/Application/FinalDeliveryUseCase.swift"
COORDINATOR="native/Sources/Application/SpeechInputCoordinator.swift"
PROVIDER="native/Sources/Application/ProviderAwareFinalASR.swift"

grep -Fq 'final_delivery_selected task_id=' "$COORDINATOR"
grep -Fq 'source=\(outcome.source)' "$COORDINATOR"
grep -Fq 'reason=\(outcome.reason)' "$COORDINATOR"
grep -Fq 'selected_backend=\(task.configuration.backend.rawValue)' "$COORDINATOR"
grep -Fq 'executed_engine=\(result.engine)' "$COORDINATOR"
grep -Fq 'final_asr_failed task_id=' "$COORDINATOR"
grep -Eq 'final_asr_result task_id=.*elapsed_ms=' "$COORDINATOR"

grep -Fq 'realtime_preview_delivery_cache' "$FINAL"
grep -Fq 'final ASR authoritative' "$FINAL"

if rg -n 'legacy candidate|legacy candidate authority' "$FINAL"; then
    echo "Final delivery reasons must describe realtime preview delivery cache, not legacy candidate authority" >&2
    exit 1
fi

if rg -n 'funasr_fallback|final=sensevoice' "$PROVIDER"; then
    echo "Selected ASR failures must not fall back to SenseVoice" >&2
    exit 1
fi

echo "FinalDeliveryLogBoundaryCheck passed"
