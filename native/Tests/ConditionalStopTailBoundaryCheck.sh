#!/usr/bin/env bash
set -euo pipefail

/usr/bin/python3 - <<'PY'
from pathlib import Path

coordinator = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()
pipeline = Path("native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift").read_text()

assert "private var stopFinalizationTaskID: UUID?" in coordinator, \
    "coordinator must guard duplicate stop requests"
assert "recording_finish_duplicate_ignored" in coordinator, \
    "duplicate stops must be observable"

finish_start = coordinator.index("    private func finishRecording(")
finish_end = coordinator.index("\n    private func startFinalRecognition", finish_start)
finish = coordinator[finish_start:finish_end]
finish_task = finish[finish.index("        Task { @MainActor"):]
ordered = [
    "await self.drainRealtimePreviewForFinalDelivery",
    "await self.finalizeRealtimePreviewTailIfNeeded",
    "realtimePreviewTextForActiveSession",
    "prepareShadowPreviewForFinalDelivery",
    "clearActiveRecording",
]
positions = [finish_task.index(token) for token in ordered]
assert positions == sorted(positions), \
    "stop order must be drain -> stopTail -> read cache -> complete cache -> clear session"
assert "guard self.activeSession?.id == taskID else" in finish_task, \
    "external cancellation during stopTail must not resume final delivery"

helper_start = coordinator.index("    private func finalizeRealtimePreviewTailIfNeeded(")
helper_end = coordinator.index("\n    private func ", helper_start + 10)
helper = coordinator[helper_start:helper_end]
assert "guard !session.reRecognizeWholeRecordingAfterStop" in helper, \
    "stopTail must be gated by the session-scoped Final ASR policy"
assert "realtime_stop_tail_skipped reason=full_final_asr_enabled" in helper
assert "recorder.makeExperimentalTailSnapshot" in helper
assert "pipeline.finishWhenCorrectionsDrained" in helper
assert "realtime_stop_tail_snapshot_failed" in helper

assert "stopFinalizationDeadlineSeconds: TimeInterval = 3" in pipeline, \
    "stop finalization must have one 3-second overall deadline"
assert "stopFinalizationDeadlineWorkItem" in pipeline
assert "preview_stop_tail_timeout" in pipeline
assert "reducer.markRecoveryRequested()" in pipeline
assert "scheduler.cancelAll()" in pipeline, \
    "deadline and cancellation must clean active as well as queued audio files"
assert "completeStopFinalization()" in pipeline, \
    "normal and timeout paths must share one-shot completion"

print("ConditionalStopTailBoundaryCheck passed")
PY
