#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
HANDOFF="$ROOT/native/Sources/Application/RecordingStopHandoff.swift"

test -f "$HANDOFF"
grep -Fq 'private var recordingStopHandoff = RecordingStopHandoff()' "$COORDINATOR"
grep -Fq 'private var pendingRecordingStart: PendingRecordingStart?' "$COORDINATOR"
grep -Fq 'queueRecordingReplacement(' "$COORDINATOR"
grep -Fq 'completeRecordingStopHandoff(' "$COORDINATOR"
grep -Fq 'recording_stop_handoff phase=accepted' "$COORDINATOR"
grep -Fq 'recording_stop_handoff phase=completed' "$COORDINATOR"

finish_body="$(sed -n '/    private func finishRecording(/,/    private func startFinalRecognition(/p' "$COORDINATOR")"
normal_finish_body="$(print -r -- "$finish_body" | sed -n '/        Task { @MainActor/,/    private func startFinalRecognition(/p')"
candidate_line="$(print -r -- "$normal_finish_body" | grep -nF 'let candidateSnapshots = await self.finishShadowPreviewForFinalDelivery(' | head -1 | cut -d: -f1)"
clear_line="$(print -r -- "$normal_finish_body" | grep -nF 'self.clearActiveRecording(' | head -1 | cut -d: -f1)"

test -n "$candidate_line"
test -n "$clear_line"
test "$candidate_line" -lt "$clear_line"

recognition_body="$(sed -n '/    private func startFinalRecognition(/,/    private func beginProductionPreview(/p' "$COORDINATOR")"
print -r -- "$recognition_body" | grep -Fq 'candidateSnapshots: FinalDeliveryCandidateSnapshots'
if print -r -- "$recognition_body" | grep -Fq 'finishShadowPreviewForFinalDelivery('; then
  print -u2 'Final recognition must consume task-scoped candidates instead of the current recording preview runtime'
  exit 1
fi

if print -r -- "$finish_body" | grep -Fq 'self.endShadowPreview(cancelled: false)'; then
  print -u2 'A late VAD callback from the old task must not tear down a newer recording preview runtime'
  exit 1
fi

print 'RecordingFinalizationHandoffBoundaryCheck passed'
