#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'longFormTranscriptionSession' "$COORDINATOR"
grep -Fq 'longFormIncrementalOutputEnabled' "$COORDINATOR"
! grep -Fq 'Timing.longFormMaxRecordingSeconds' "$COORDINATOR"
grep -Fq 'long_form_incremental_final' "$COORDINATOR"
grep -Fq 'handle(.recognized(FinalRecognitionResult(' "$COORDINATOR"
grep -Fq 'finalizeRealtimePreviewTailIfNeeded' "$COORDINATOR"
grep -Fq 'realtime_stop_tail_skipped reason=full_final_asr_enabled' "$COORDINATOR"
grep -Fq 'session.reRecognizeWholeRecordingAfterStop' "$COORDINATOR"
grep -Fq 'volumeAvailableCapacityForImportantUsage' "$COORDINATOR"
grep -Fq 'long_form_low_disk' "$COORDINATOR"
grep -Fq 'longFormFinalizationTaskIDs.isEmpty' "$COORDINATOR"
grep -Fq 'longFormPersistenceQueue.async' "$COORDINATOR"
grep -Fq 'drainCompletedExperimentalSnapshots' "$COORDINATOR"
grep -Fq 'guard isMeaningfulRecognitionText(transcript)' "$COORDINATOR"
grep -Fq 'usesNoTextTimeout' "$COORDINATOR"
grep -Fq 'usesPauseAutoFinish' "$COORDINATOR"

echo "LongFormCoordinatorBoundaryCheck passed"
