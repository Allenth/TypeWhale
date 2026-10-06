#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HEADER="$ROOT_DIR/native/TypeSpeakerNativeASR.h"
SOURCE="$ROOT_DIR/native/TypeSpeakerNativeASR.c"

grep -Fq 'TypeSpeakerNativeParakeetRecognizerCreate(' "$HEADER"
grep -Fq 'const char *encoder_path' "$HEADER"
grep -Fq 'const char *decoder_path' "$HEADER"
grep -Fq 'const char *joiner_path' "$HEADER"
grep -Fq 'config.model_config.transducer.encoder = encoder_path;' "$SOURCE"
grep -Fq 'config.model_config.model_type = "nemo_transducer";' "$SOURCE"
grep -Fq 'config.decoding_method = "greedy_search";' "$SOURCE"

echo "SherpaCandidateBridgeBoundaryCheck passed"
