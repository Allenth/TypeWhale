#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"
STATE="$ROOT/native/Sources/Application/SpeechInputState.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
PIPELINE="$ROOT/native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift"
BRIDGE="$ROOT/native/Sources/Infrastructure/ASR/SenseVoiceASR.swift"
HEADER="$ROOT/native/TypeSpeakerNativeASR.h"
NATIVE="$ROOT/native/TypeSpeakerNativeASR.c"

grep -Fq 'var onRealtimeSnapshot: ((UUID, [Float], Int, Int, Bool, TimeInterval, PreviewAudioRange) -> Void)?' "$AUDIO"
grep -Fq 'audioRange: PreviewAudioRange' "$STATE"
grep -Fq 'audioRange: request.audioRange' "$PIPELINE"
grep -Fq 'let samples: [Float]' "$STATE"
grep -Fq 'let sampleRate: Int' "$STATE"
grep -Fq 'func transcribe(' "$BRIDGE"
grep -Fq 'samples: [Float],' "$BRIDGE"
grep -Fq 'TypeSpeakerNativeRecognizerTranscribeSamples' "$HEADER"
grep -Fq 'TypeSpeakerNativeRecognizerTranscribeSamples' "$NATIVE"
grep -Fq 'realtimeASR.transcribe(' "$COORDINATOR"
grep -Fq 'samples: request.samples' "$COORDINATOR"

python3 - "$AUDIO" "$STATE" "$COORDINATOR" <<'PY'
from pathlib import Path
import sys

audio = Path(sys.argv[1]).read_text()
state = Path(sys.argv[2]).read_text()
coordinator = Path(sys.argv[3]).read_text()

if '".realtime-' in audio:
    raise SystemExit("product realtime preview must not create .realtime-*.wav files")

request_start = state.index("struct RealtimeSnapshotRequest")
request_end = state.index("struct PendingPasteResult")
request = state[request_start:request_end]
if "audioURL: URL" in request:
    raise SystemExit("RealtimeSnapshotRequest must not require a file URL")

transcribe_start = coordinator.index("private func transcribeRealtime")
transcribe_end = coordinator.index("private func applyRealtimePreview", transcribe_start)
transcribe = coordinator[transcribe_start:transcribe_end]
if "audio:" in transcribe or "FileManager.default.removeItem" in transcribe:
    raise SystemExit("product realtime transcribe must not depend on realtime wav files")

receive_start = coordinator.index("private func receiveRealtimeSnapshot")
receive_end = coordinator.index("private func receiveExperimentalCorrectionSnapshot", receive_start)
receive = coordinator[receive_start:receive_end]
if "FileManager.default.removeItem" in receive or "url:" in receive:
    raise SystemExit("product realtime receive path must be memory-only")
PY

echo "RealtimePreviewMemoryAudioBoundaryCheck passed"
