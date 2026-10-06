#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotNativeRecognizer.swift"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'final class SenseVoiceSnapshotNativeRecognizer' "$SOURCE"
grep -Fq 'bridge.transcribeDetailed' "$SOURCE"
grep -Fq 'try? FileManager.default.removeItem(at: audioURL)' "$SOURCE"
grep -Fq 'SenseVoiceSnapshotRecognitionOutput' "$SOURCE"
grep -Fq 'final class NativeSenseVoiceBridge: @unchecked Sendable' "$ROOT/native/Sources/Infrastructure/ASR/SenseVoiceASR.swift"
grep -Fq -- '--debug-shadow-sensevoice' "$SPEECH"
grep -Fq 'NativeSenseVoiceBridge(runtimeName: "shadow")' "$SPEECH"
grep -Fq 'SenseVoiceSnapshotProvider(' "$SPEECH"

if rg -n 'PreviewSourceLane|PreviewPipelineRequest|RecordingPanel|ShadowPreview' "$SOURCE" >/dev/null; then
  echo "Native snapshot adapter leaked legacy or presentation concepts" >&2
  exit 1
fi

echo "SenseVoiceSnapshotNativeRecognizerSourceCheck passed"
