#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKER="${TYPEWHALE_TTSKIT_WORKER:-$ROOT/native/Helpers/TTSKitBridge/.build/release/typewhale-ttskit-worker}"
MODEL_ROOT="${TYPEWHALE_TTS_MODEL_ROOT:-$HOME/Library/Application Support/TypeWhale Pro/Models/tts}"
REPORT_ROOT="${TYPEWHALE_TTS_REPORT_ROOT:-/tmp/typewhale-ttskit-probe}"

mkdir -p "$REPORT_ROOT"

run_variant() {
  local model_id="$1"
  local variant="$2"
  local model="$MODEL_ROOT/$model_id"
  local report="$REPORT_ROOT/$model_id.jsonl"
  local zh_wav="$REPORT_ROOT/$model_id-zh.wav"
  local en_wav="$REPORT_ROOT/$model_id-en.wav"
  local mixed_wav="$REPORT_ROOT/$model_id-mixed.wav"

  [[ -f "$model/tokenizer/tokenizer.json" ]]
  [[ -f "$model/tokenizer/tokenizer_config.json" ]]

  printf '%s\n' \
    '{"id":"prepare","type":"prepare"}' \
    "{\"id\":\"zh\",\"type\":\"synthesize\",\"text\":\"你好，欢迎使用 TypeWhale 本地朗读测试。\",\"output\":\"$zh_wav\"}" \
    "{\"id\":\"en\",\"type\":\"synthesize\",\"text\":\"The quick brown fox jumps over the lazy dog.\",\"output\":\"$en_wav\"}" \
    "{\"id\":\"mixed\",\"type\":\"synthesize\",\"text\":\"TypeWhale 使用 Core ML 完成本地测试。\",\"output\":\"$mixed_wav\"}" \
    '{"id":"shutdown","type":"shutdown"}' |
    env HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 NO_PROXY='*' \
      "$WORKER" --model-root "$model" --variant "$variant" >"$report"

  grep -q '"id":"zh".*"phase":"completed"' "$report"
  grep -q '"id":"en".*"phase":"completed"' "$report"
  grep -q '"id":"mixed".*"phase":"completed"' "$report"
  for wav in "$zh_wav" "$en_wav" "$mixed_wav"; do
    [[ -s "$wav" ]]
    /usr/bin/afinfo "$wav" | grep -q 'estimated duration'
  done
}

run_variant qwen3-tts-06b-coreml 0.6b
run_variant qwen3-tts-17b-coreml 1.7b
echo "TTSKitCoreMLProbe passed"
