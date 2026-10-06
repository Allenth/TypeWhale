#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
FAKE="$ROOT/native/Sources/Infrastructure/RealtimeTranscription/FakeStreamingProvider.swift"

grep -Fq -- '--debug-shadow-fake-stream' "$SPEECH"
grep -Fq 'ProcessInfo.processInfo.arguments.contains' "$SPEECH"
grep -Fq 'FakeStreamingProvider' "$SPEECH"

if rg -n 'AppKit|PreviewViewState|ShadowPreview|RecordingPanel|SpeechInputCoordinator' "$FAKE" >/dev/null; then
  echo "FakeStreamingProvider must remain infrastructure-only and presentation-agnostic" >&2
  exit 1
fi

echo "FakeStreamingShadowInjectionCheck passed"
