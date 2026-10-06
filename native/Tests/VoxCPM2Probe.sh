#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME="${TYPEWHALE_VOXCPM_RUNTIME:-$HOME/Library/Application Support/TypeWhale Pro/Runtimes/tts/voxcpm2-2.0.3-py312}"
MODEL="${TYPEWHALE_VOXCPM_MODEL:-$HOME/Library/Application Support/TypeWhale Pro/Models/tts/voxcpm2}"
REPORT="${TYPEWHALE_VOXCPM_REPORT:-/tmp/typewhale-voxcpm2-probe.jsonl}"
OUTPUT="${TYPEWHALE_VOXCPM_OUTPUT:-/tmp/typewhale-voxcpm2-probe.wav}"

printf '%s\n' \
  '{"id":"prepare","type":"prepare"}' \
  "{\"id\":\"zh\",\"type\":\"synthesize\",\"text\":\"你好，欢迎使用 TypeWhale 本地朗读测试。\",\"output\":\"$OUTPUT\"}" \
  '{"id":"shutdown","type":"shutdown"}' |
  env HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 NO_PROXY='*' \
    "$RUNTIME/bin/python3" "$ROOT/native/Resources/tts_benchmark_worker.py" \
      --engine voxcpm2-python-mps --pack "$MODEL" >"$REPORT"

grep -q '"id": "zh".*"phase": "completed"' "$REPORT"
[[ -s "$OUTPUT" ]]
/usr/bin/afinfo "$OUTPUT" | grep -q 'estimated duration'
echo "VoxCPM2Probe passed"
