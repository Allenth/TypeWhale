#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'func subscribeToAudioFrames(capacity:' "$SOURCE"
grep -Fq 'audioFrameFanOut.offer' "$SOURCE"
grep -Fq 'var onRealtimeSnapshot:' "$SOURCE"
grep -Fq 'var onExperimentalPreviewSnapshot:' "$SOURCE"
grep -Fq 'var onVoiceProbe:' "$SOURCE"
grep -Fq 'shadowAudioFrameTask' "$SPEECH"
grep -Fq 'recorder.subscribeToAudioFrames' "$SPEECH"
grep -Fq 'case .overflow' "$SPEECH"

python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
write = source.index("try file.write(from: canonical)")
offer = source.index("audioFrameFanOut.offer", write)
if offer < write:
    raise SystemExit("fan-out must happen after the production file write")
PY

echo "AudioRecorderFanOutSourceCheck passed"
