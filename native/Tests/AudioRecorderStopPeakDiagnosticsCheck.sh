#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RECORDER="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

grep -Fq 'recorder_stop_audio' "$RECORDER"
grep -Fq 'peak=' "$RECORDER"
grep -Fq 'frames=' "$RECORDER"

echo "AudioRecorderStopPeakDiagnosticsCheck passed"
