#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPTURE="$ROOT/native/Sources/Infrastructure/Audio/ManualAudioInputCapture.swift"

grep -Fq 'mChannelsPerFrame: 1' "$CAPTURE"
grep -Fq 'AVAudioChannelCount(1)' "$CAPTURE"
grep -Fq 'Built-in MacBook microphone can expose 3 hardware channels' "$CAPTURE"
! grep -Fq 'channels: hardware.mChannelsPerFrame' "$CAPTURE"

echo "ManualAudioInputCaptureMonoClientFormatCheck passed"
