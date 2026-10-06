#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

grep -Fq 'kAudioOutputUnitProperty_EnableIO' "$AUDIO"
grep -Fq 'kAudioUnitProperty_StreamFormat' "$AUDIO"
grep -Fq 'kAudioUnitScope_Input' "$AUDIO"
grep -Fq 'kAudioUnitScope_Output' "$AUDIO"
grep -Fq 'verifyBoundInputDevice' "$AUDIO"
grep -Fq 'audio_input_device_bound' "$AUDIO"

echo "AudioInputBindingBoundaryCheck passed"
