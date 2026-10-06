#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

STOP_BODY="$(sed -n '/    func stop() throws/,/    func cancel()/p' "$AUDIO")"

wait_line="$(printf '%s\n' "$STOP_BODY" | grep -nF 'processingGroup.wait()' | head -1 | cut -d: -f1)"
close_line="$(printf '%s\n' "$STOP_BODY" | grep -nF 'currentFile = nil' | head -1 | cut -d: -f1)"
finalize_line="$(printf '%s\n' "$STOP_BODY" | grep -nF 'try writeFinalRecording(from: pendingURL, to: taskURL)' | head -1 | cut -d: -f1)"

test -n "$wait_line"
test -n "$close_line"
test -n "$finalize_line"
test "$wait_line" -lt "$close_line"
test "$close_line" -lt "$finalize_line"

echo "AudioRecorderFinalizationBoundaryCheck passed"
