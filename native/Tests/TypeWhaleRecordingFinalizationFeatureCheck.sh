#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-recording-finalization.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
  "$ROOT/native/Sources/Application/RecordingStopHandoff.swift" \
  "$ROOT/native/Tests/RecordingStopHandoffCheck.swift" \
  -o "$OUT/RecordingStopHandoffCheck"
"$OUT/RecordingStopHandoffCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Application/SpeechWorkflowState.swift" \
  "$ROOT/native/Tests/SpeechWorkflowStateCheck.swift" \
  -o "$OUT/SpeechWorkflowStateCheck"
"$OUT/SpeechWorkflowStateCheck"

for check in \
  RecordingFinalizationHandoffBoundaryCheck.sh \
  AudioRecorderFinalizationBoundaryCheck.sh \
  AudioRecorderExternalPCMBoundaryCheck.sh \
  SpeechInputCoordinatorBoundaryCheck.sh \
  RemoteSpeechCoordinatorBoundaryCheck.sh
do
  /bin/zsh "$ROOT/native/Tests/$check"
done

print 'TypeWhaleRecordingFinalizationFeatureCheck passed'
