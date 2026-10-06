#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$ROOT/tools/openclaw_sherpa_native_tts_probe.sh"

test -x "$PROBE"
grep -q 'TYPEWHALE_SHERPA_NATIVE_TTS' "$PROBE"
grep -q 'TYPEWHALE_SHERPA_TTS_PACK' "$PROBE"
grep -q 'sherpa-onnx-offline-tts' "$PROBE"
grep -q 'sherpa_typewhale_lexicon.txt' "$PROBE"
grep -q 'lexicon.typewhale.txt' "$PROBE"
grep -q 'model.int8.onnx' "$PROBE"
grep -q 'model.onnx' "$PROBE"
! grep -q 'python' "$PROBE"
! grep -q 'pip' "$PROBE"

echo "SherpaNativeTTSProbeCheck passed"
