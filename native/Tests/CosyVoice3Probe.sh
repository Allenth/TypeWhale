#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME="${TYPEWHALE_COSY_RUNTIME:-$HOME/Library/Application Support/TypeWhale Pro/Runtimes/tts/cosyvoice3-main-py310}"
SOURCE="$RUNTIME/src/CosyVoice"
MODEL="${TYPEWHALE_COSY_MODEL:-$HOME/Library/Application Support/TypeWhale Pro/Models/tts/fun-cosyvoice3-0.5b-2512}"
REPORT="${TYPEWHALE_COSY_REPORT:-/tmp/typewhale-cosyvoice3-probe.jsonl}"
OUTPUT="${TYPEWHALE_COSY_OUTPUT:-/tmp/typewhale-cosyvoice3-probe.wav}"

printf '%s\n' \
  '{"id":"prepare","type":"prepare"}' \
  "{\"id\":\"zh\",\"type\":\"synthesize\",\"text\":\"你好，欢迎使用 TypeWhale 本地朗读测试。\",\"output\":\"$OUTPUT\"}" \
  '{"id":"shutdown","type":"shutdown"}' |
  env HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 NO_PROXY='*' \
    TYPEWHALE_COSYVOICE_SOURCE="$SOURCE" \
    PYTHONPATH="$SOURCE:$SOURCE/third_party/Matcha-TTS" \
    "$RUNTIME/bin/python3" "$ROOT/native/Resources/tts_benchmark_worker.py" \
      --engine cosyvoice3-python-cpu --pack "$MODEL" >"$REPORT"

grep -q '"id": "zh".*"phase": "completed"' "$REPORT"
[[ -s "$OUTPUT" ]]
/usr/bin/afinfo "$OUTPUT" | grep -q 'estimated duration'
echo "CosyVoice3Probe passed (CPU compatibility runtime)"
