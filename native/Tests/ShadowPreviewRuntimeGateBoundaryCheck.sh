#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
GATE="$ROOT/native/Sources/Application/RealtimeTranscription/ShadowPreviewRuntimeGate.swift"

if [ ! -f "$GATE" ]; then
  echo "ShadowPreviewRuntimeGate must exist as the single runtime gate." >&2
  exit 1
fi

if ! grep -q "ShadowPreviewRuntimeGate.shouldStart" "$COORDINATOR"; then
  echo "beginShadowPreview must use ShadowPreviewRuntimeGate.shouldStart before creating runtime." >&2
  exit 1
fi

if ! grep -q "ShadowPreviewRuntimeGate.shouldPublish" "$COORDINATOR"; then
  echo "publishShadowPreview must use ShadowPreviewRuntimeGate.shouldPublish before publishing snapshots." >&2
  exit 1
fi

if ! grep -q "shadowPreviewCoordinator.end()" "$COORDINATOR"; then
  echo "Shadow coordinator must still be ended during teardown." >&2
  exit 1
fi

if grep -q "candidatePreviewCoordinator" "$COORDINATOR"; then
  echo "Retired candidate coordinator must not remain in the runtime gate path." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|PasteCoordinator|TranscriptionProvider|SenseVoiceSnapshotProvider|OnlineTranscriptionProvider|MiMoSnapshotProvider|DoubaoStreamingTransport'
if grep -E "$FORBIDDEN_PATTERN" "$GATE" >/dev/null; then
  echo "Runtime gate must not depend on delivery, provider, ASR, or paste paths." >&2
  exit 1
fi

echo "ShadowPreviewRuntimeGateBoundaryCheck passed"
