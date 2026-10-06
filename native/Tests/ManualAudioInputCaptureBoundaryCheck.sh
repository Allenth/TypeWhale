#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPTURE="$ROOT/native/Sources/Infrastructure/Audio/ManualAudioInputCapture.swift"
RECORDER="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"
test -f "$CAPTURE"
grep -Fq 'kAudioUnitSubType_HALOutput' "$CAPTURE"
grep -Fq 'AudioUnitRender' "$CAPTURE"
grep -Fq 'standardFormatWithSampleRate: sampleRate' "$CAPTURE"
grep -Fq 'mChannelsPerFrame: 1' "$CAPTURE"
grep -Fq 'manualCapture' "$RECORDER"
grep -Fq 'ManualAudioInputCapture(deviceID:' "$RECORDER"
echo "ManualAudioInputCaptureBoundaryCheck passed"
