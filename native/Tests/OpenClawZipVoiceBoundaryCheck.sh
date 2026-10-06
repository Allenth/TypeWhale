#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETTINGS="$ROOT/native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift"
VOICE_CATALOG="$ROOT/native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift"
PLAYER="$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
WORKER="$ROOT/native/Resources/tts_benchmark_worker.py"

grep -q 'case zipVoice = "zipvoice"' "$SETTINGS"
grep -q '"zipvoice-default"' "$SETTINGS"
grep -q '"zipvoice-serena"' "$VOICE_CATALOG"
grep -q '"zipvoice-cosy"' "$VOICE_CATALOG"
grep -q '"zipvoice-video-reference"' "$VOICE_CATALOG"
grep -q 'personalVoice' "$VOICE_CATALOG"
grep -q 'tts/zipvoice-distill-int8-zh-en-emilia' "$SETTINGS"
grep -q 'resourceName = "tts_benchmark_worker"' "$PLAYER"
grep -q '"--engine", "sherpa-zipvoice"' "$PLAYER"
grep -q 'payload\["voiceID"\] = voiceID' "$PLAYER"
grep -q 'response.voiceID != voiceID' "$PLAYER"
grep -q 'func cancelSynthesis()' "$PLAYER"
grep -q 'stop()' "$PLAYER"
grep -q 'if self.engine == "sherpa-zipvoice"' "$WORKER"
grep -q 'voice_id or "zipvoice-default"' "$WORKER"

reject() {
  local pattern="$1"
  local file="$2"
  if grep -q "$pattern" "$file"; then
    echo "Retired TTS reference remains: $pattern in $file" >&2
    exit 1
  fi
}

reject 'case meloTTS' "$SETTINGS"
reject 'case sherpaMelo' "$SETTINGS"
reject 'MeloTTSVoicePack' "$PLAYER"
reject 'SherpaMeloTTSVoicePack' "$PLAYER"
reject 'sherpa-kokoro' "$WORKER"
reject 'sherpa-vits' "$WORKER"
reject 'cosyvoice3-python' "$WORKER"
reject 'moss-python' "$WORKER"
reject 'voxcpm2-python' "$WORKER"

echo "OpenClawZipVoiceBoundaryCheck passed"
