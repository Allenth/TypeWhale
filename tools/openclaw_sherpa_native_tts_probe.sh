#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACK="${TYPEWHALE_SHERPA_TTS_PACK:-$HOME/Library/Application Support/TypeWhale Pro/Models/tts/sherpa-vits-melo-tts-zh_en}"
TEXT="${1:-OpenClaw 正在测试 GitHub、MiniMax、OpenAI、API、Kubernetes 和 TypeScript。}"
OUTPUT="${2:-/tmp/typewhale-sherpa-native-probe.wav}"

if [[ -n "${TYPEWHALE_SHERPA_NATIVE_TTS:-}" ]]; then
  EXE="$TYPEWHALE_SHERPA_NATIVE_TTS"
elif [[ -x "$PACK/runtime/native/sherpa-onnx-offline-tts" ]]; then
  EXE="$PACK/runtime/native/sherpa-onnx-offline-tts"
elif command -v sherpa-onnx-offline-tts >/dev/null 2>&1; then
  EXE="$(command -v sherpa-onnx-offline-tts)"
else
  echo "Missing native sherpa-onnx-offline-tts. Set TYPEWHALE_SHERPA_NATIVE_TTS to an executable." >&2
  exit 2
fi

MODEL="$PACK/model.onnx"
if [[ ! -f "$MODEL" && -f "$PACK/model.int8.onnx" ]]; then
  MODEL="$PACK/model.int8.onnx"
fi

for required in "$MODEL" "$PACK/lexicon.txt" "$PACK/tokens.txt" "$PACK/dict" "$PACK/number.fst" "$PACK/phone.fst" "$PACK/date.fst"; do
  if [[ ! -e "$required" ]]; then
    echo "Missing Sherpa TTS resource: $required" >&2
    exit 3
  fi
done

LEXICON="$PACK/lexicon.txt"
CUSTOM="$ROOT/native/Resources/sherpa_typewhale_lexicon.txt"
if [[ -f "$CUSTOM" ]]; then
  mkdir -p "$PACK/.typewhale"
  LEXICON="$PACK/.typewhale/lexicon.typewhale.txt"
  {
    sed '/^[[:space:]]*$/d' "$CUSTOM"
    cat "$PACK/lexicon.txt"
  } > "$LEXICON"
fi

SECONDS=0
"$EXE" \
  --vits-model "$MODEL" \
  --vits-lexicon "$LEXICON" \
  --vits-tokens "$PACK/tokens.txt" \
  --vits-dict-dir "$PACK/dict" \
  --tts-rule-fsts "$PACK/phone.fst,$PACK/number.fst,$PACK/date.fst" \
  --output-filename "$OUTPUT" \
  "$TEXT"

test -s "$OUTPUT"
echo "wrote=$OUTPUT"
echo "seconds=$SECONDS"
echo "exe=$EXE"
