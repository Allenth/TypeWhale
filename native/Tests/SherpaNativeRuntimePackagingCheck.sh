#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/native/build_native_app.sh"

grep -q 'TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME' "$BUILD"
grep -q 'NativeTTS/sherpa' "$BUILD"
grep -q 'bin/sherpa-onnx-offline-tts' "$BUILD"
grep -q 'for RUNTIME_DIR in "\$NATIVE_ASR_LIB" "\$NATIVE_TTS"' "$BUILD"
grep -q 'codesign --force --sign "\$SIGN_IDENTITY" "\$file"' "$BUILD"

echo "SherpaNativeRuntimePackagingCheck passed"
