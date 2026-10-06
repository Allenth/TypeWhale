#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME="$(mktemp -d /tmp/typewhale-native-tts-runtime.XXXXXX)"
APP_NAME="TypeWhale Pro TTS Package Check"
APP="$ROOT/macos/$APP_NAME.app"

cleanup() {
  rm -rf "$RUNTIME" "$APP"
}
trap cleanup EXIT

mkdir -p "$RUNTIME/bin" "$RUNTIME/lib"
printf '#!/bin/zsh\nexit 0\n' > "$RUNTIME/bin/sherpa-onnx-offline-tts"
chmod +x "$RUNTIME/bin/sherpa-onnx-offline-tts"

TYPEWHALE_APP_DISPLAY_NAME="$APP_NAME" \
TYPEWHALE_APP_EXECUTABLE="TypeWhaleProTTSPackageCheck" \
TYPEWHALE_APP_BUNDLE_IDENTIFIER="com.waykingah.typewhale.pro.tts-package-check" \
TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME="$RUNTIME" \
TYPESPEAKER_SKIP_INSTALL=1 \
"$ROOT/native/build_native_app.sh"

test -x "$APP/Contents/Resources/NativeTTS/sherpa/bin/sherpa-onnx-offline-tts"
codesign --verify --deep --strict "$APP"

echo "SherpaNativeRuntimePackagingIntegrationCheck passed"
