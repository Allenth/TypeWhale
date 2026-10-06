#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

grep -Fq 'private let realtimeChunkBoundaryPolicy = RealtimeChunkBoundaryPolicy()' "$AUDIO"
grep -Fq 'private var realtimeVoiceObserved = false' "$AUDIO"
grep -Fq 'realtimeVoiceObserved = false' "$AUDIO"
grep -Fq 'realtimeChunkBoundaryPolicy.shouldFinalize(' "$AUDIO"
grep -Fq 'chunkIndex: realtimeChunkIndex' "$AUDIO"
grep -Fq 'hasObservedVoice: realtimeVoiceObserved' "$AUDIO"
grep -Fq 'if active { self.realtimeVoiceObserved = true }' "$AUDIO"
! grep -Fq 'static let chunkSoftSeconds: Double = 10.0' "$AUDIO"

echo "RealtimeChunkBoundaryPolicyWiringCheck passed"
