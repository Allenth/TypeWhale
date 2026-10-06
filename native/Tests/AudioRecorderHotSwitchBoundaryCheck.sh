#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

grep -Fq 'func switchInput(' "$AUDIO"
grep -Fq 'CanonicalAudioConverter' "$AUDIO"
grep -Fq 'case switching' "$AUDIO"
grep -Fq 'switchGeneration' "$AUDIO"
grep -Fq 'processingGroup.wait()' "$AUDIO"
! grep -Fq 'cancelForInputRouteChange(message)' "$AUDIO"

echo "AudioRecorderHotSwitchBoundaryCheck passed"
