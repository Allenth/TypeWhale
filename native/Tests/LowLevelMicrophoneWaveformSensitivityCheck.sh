#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RECORDER="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"
UI="$ROOT/native/Sources/Presentation/Shared/UIComponents.swift"

# Built-in MacBook microphone capture can produce valid, recognizable speech around peak=0.001.
# The waveform must not gate that level as visual silence.
grep -Fq 'lowLevelSpeechFloor' "$RECORDER"
grep -Fq 'lowLevelSpeechReference' "$RECORDER"
grep -Fq 'let broadband = min(1, rms / Self.lowLevelSpeechReference)' "$RECORDER"
grep -Fq 'static let activityFloor' "$UI"
grep -Fq 'static let activityRange' "$UI"
! grep -Fq 'band) - 0.16' "$UI"

echo "LowLevelMicrophoneWaveformSensitivityCheck passed"
