#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PYTHON="${TYPEWHALE_MOSS_PYTHON:-/usr/local/bin/python3}"
WORKER="$ROOT/native/Resources/tts_benchmark_worker.py"
MODEL="${TYPEWHALE_MOSS_MODEL:-$HOME/Library/Application Support/TypeWhale Pro/Models/tts/moss-tts-local-transformer-v1.5}"
REPORT="${TYPEWHALE_MOSS_REPORT:-/tmp/typewhale-moss-probe.jsonl}"
OUTPUT="${TYPEWHALE_MOSS_OUTPUT:-/tmp/typewhale-moss-probe.wav}"

[[ -f "$MODEL/model.safetensors" ]]
[[ -f "$MODEL/audio-tokenizer-v2/model.safetensors.index.json" ]] || {
  echo "runtime_unavailable: missing audio-tokenizer-v2 assets" >&2
  exit 2
}

printf '%s\n' \
  '{"id":"prepare","type":"prepare"}' \
  "{\"id\":\"zh\",\"type\":\"synthesize\",\"text\":\"你好，欢迎使用 TypeWhale 本地朗读测试。\",\"output\":\"$OUTPUT\"}" \
  '{"id":"shutdown","type":"shutdown"}' |
  env HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 NO_PROXY='*' \
    "$PYTHON" "$WORKER" --engine moss-python-mps --pack "$MODEL" >"$REPORT"

grep -q '"id": "zh".*"phase": "completed"' "$REPORT"
[[ -s "$OUTPUT" ]]
/usr/bin/afinfo "$OUTPUT" | grep -q 'estimated duration'
echo "MOSSTorchFreeProbe passed (managed Python/MPS fallback)"
