#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
FILTER="$ROOT/native/Sources/Domain/Text/RecognitionTextFilter.swift"

grep -Fq 'latestVoiceProbeHasSpeech' "$SOURCE"
grep -Fq 'latestVoiceProbeCapturedAt' "$SOURCE"
grep -Fq 'shouldSkipRealtimeASRForSilence' "$SOURCE"
grep -Fq 'guard request.isChunkFinal else { return false }' "$SOURCE"
grep -Fq 'realtime_snapshot_skipped_silence' "$SOURCE"
grep -Fq '"我想"' "$FILTER"
grep -Fq '"i"' "$FILTER"

python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()

start = source.index("private func transcribeRealtime")
end = source.index("private func applyRealtimePreview", start)
transcribe = source[start:end]

gate = transcribe.find("shouldSkipRealtimeASRForSilence")
asr = transcribe.find("realtimeASR.transcribe")
if gate == -1 or asr == -1 or gate > asr:
    raise SystemExit("transcribeRealtime must check silence gate before realtimeASR.transcribe")

if 'request.isChunkFinal' not in transcribe or 'applyRealtimePreview(request: request' not in transcribe:
    raise SystemExit("silent final chunk must still freeze current preview state")

gate_start = source.index("private func shouldSkipRealtimeASRForSilence")
gate_end = source.index("/// 把某个块快照的识别结果合并进预览", gate_start)
gate_body = source[gate_start:gate_end]
if "guard request.isChunkFinal else { return false }" not in gate_body:
    raise SystemExit("silence gate must only skip final chunk snapshots")

probe_start = source.index("private func startVoiceProbe")
probe_end = source.index("private func handleAutoFinishDecision", probe_start)
probe = source[probe_start:probe_end]
if "latestVoiceProbeHasSpeech = true" not in probe:
    raise SystemExit("voice probe success(true) must update latestVoiceProbeHasSpeech")
if "latestVoiceProbeHasSpeech = false" not in probe:
    raise SystemExit("voice probe success(false) must update latestVoiceProbeHasSpeech")
PY

echo "RealtimeSilenceGateBoundaryCheck passed"
