#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
FINAL_DELIVERY="$ROOT/native/Sources/Application/FinalDeliveryUseCase.swift"

grep -Fq 'candidate_delivery_cache task_id=' "$COORDINATOR"
grep -Fq 'final_delivery_selected task_id=' "$COORDINATOR"
grep -Fq 'source=\(outcome.source)' "$COORDINATOR"
grep -Fq 'reason=\(outcome.reason)' "$COORDINATOR"
grep -Fq 'final_asr_result task_id=' "$COORDINATOR"
grep -Fq 'final_asr_empty task_id=' "$COORDINATOR"
grep -Fq 'shadow_sensevoice_summary accepted_frames=' "$COORDINATOR"
grep -Fq 'tail_gap_ms=' "$COORDINATOR"
grep -Fq 'seam_confidence=' "$COORDINATOR"
grep -Fq 'shadow_online_summary provider=' "$COORDINATOR"
grep -Fq 'paste_drain task_id=' "$COORDINATOR"

grep -Fq 'quality=accepted quality_reason=accepted' "$FINAL_DELIVERY"
grep -Fq 'quality=rejected quality_reason=' "$FINAL_DELIVERY"
grep -Fq 'realtime_preview_delivery_cache' "$FINAL_DELIVERY"

echo "RealtimeRecognitionDiagnosticsBoundaryCheck passed"
