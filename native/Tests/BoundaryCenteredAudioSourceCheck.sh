#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

grep -Fq 'experimentalPreviewEnabled: Bool = false' "$AUDIO"
grep -Fq 'onExperimentalPreviewSnapshot' "$AUDIO"
grep -Fq 'experimentalContextBuffers' "$AUDIO"
grep -Fq 'pendingExperimentalBoundary' "$AUDIO"
grep -Fq 'emitBoundaryCenteredSnapshot' "$AUDIO"
grep -Fq 'experimentalContextBuffers = []' "$AUDIO"
grep -Fq 'makeExperimentalTailSnapshot' "$AUDIO"
grep -Fq 'source.framePosition = startFrame' "$AUDIO"
grep -Fq 'drainCompletedExperimentalSnapshots' "$AUDIO"
grep -Fq 'snapshotQueue.sync' "$AUDIO"

echo "BoundaryCenteredAudioSourceCheck passed"
