#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/macos/TypeWhale.app"
CONTENTS="$APP/Contents"
SHERPA_ROOT="${TYPESPEAKER_SHERPA_ROOT:-/Library/Frameworks/Python.framework/Versions/3.10/lib/python3.10/site-packages/sherpa_onnx}"
NATIVE_ASR="$CONTENTS/Resources/NativeASR"
NATIVE_ASR_LIB="$NATIVE_ASR/lib"
NATIVE_ASR_OBJECT="$ROOT/native/.TypeSpeakerNativeASR.o"
LAUNCH_PROBE_OBJECT="$ROOT/native/.LaunchProbe.o"
BUNDLED_MODELS="$CONTENTS/Resources/Models"
BUNDLED_SENSEVOICE="$BUNDLED_MODELS/sensevoice-native"
BUNDLED_VAD="$BUNDLED_MODELS/vad"
THIRD_PARTY_NOTICES="$ROOT/THIRD_PARTY_NOTICES.md"

if [[ -n "${TYPESPEAKER_MODEL_SOURCE:-}" ]]; then
  MODEL_SOURCE="$TYPESPEAKER_MODEL_SOURCE"
else
  MODEL_SOURCE=""
  for candidate in \
    "$HOME/Library/Application Support/TypeWhale/Models/sensevoice-native" \
    "$ROOT/macos/TypeWhale.app/Contents/Resources/Models/sensevoice-native"; do
    if [[ -f "$candidate/model.onnx" && -f "$candidate/tokens.txt" ]]; then
      MODEL_SOURCE="$candidate"
      break
    fi
  done
fi

MODEL_SOURCE_TEMP=""
if [[ -n "$MODEL_SOURCE" && "$MODEL_SOURCE" == "$APP/"* ]]; then
  MODEL_SOURCE_TEMP="$(mktemp -d /tmp/typewhale-model-source.XXXXXX)"
  cp "$MODEL_SOURCE/model.onnx" "$MODEL_SOURCE_TEMP/model.onnx"
  cp "$MODEL_SOURCE/tokens.txt" "$MODEL_SOURCE_TEMP/tokens.txt"
  MODEL_SOURCE="$MODEL_SOURCE_TEMP"
fi
trap '[[ -n "${MODEL_SOURCE_TEMP:-}" ]] && rm -rf "$MODEL_SOURCE_TEMP"' EXIT

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
find "$CONTENTS/Resources" -name __pycache__ -type d -prune -exec rm -rf {} +
if [[ ! -f "$THIRD_PARTY_NOTICES" ]]; then
  echo "Missing third-party notices: $THIRD_PARTY_NOTICES" >&2
  exit 1
fi
cp "$THIRD_PARTY_NOTICES" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"

if [[ ! -f "$SHERPA_ROOT/include/sherpa-onnx/c-api/c-api.h" ]]; then
  echo "Missing sherpa-onnx C API header: $SHERPA_ROOT/include/sherpa-onnx/c-api/c-api.h" >&2
  exit 1
fi

rm -rf "$NATIVE_ASR"
mkdir -p "$NATIVE_ASR_LIB"
cp "$SHERPA_ROOT/lib/libsherpa-onnx-c-api.dylib" "$NATIVE_ASR_LIB/"
cp "$SHERPA_ROOT/lib/libonnxruntime.1.24.4.dylib" "$NATIVE_ASR_LIB/"

if [[ ! -f "$MODEL_SOURCE/model.onnx" || ! -f "$MODEL_SOURCE/tokens.txt" ]]; then
  echo "Missing bundled SenseVoice model files in: $MODEL_SOURCE" >&2
  echo "Expected model.onnx and tokens.txt. Set TYPESPEAKER_MODEL_SOURCE to override." >&2
  exit 1
fi
VAD_SOURCE="${TYPEWHALE_VAD_MODEL_SOURCE:-$HOME/Library/Application Support/TypeWhale/Models/vad/silero_vad.onnx}"
if [[ ! -f "$VAD_SOURCE" ]]; then
  echo "Missing Silero VAD model file: $VAD_SOURCE" >&2
  echo "Download it from: https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx" >&2
  exit 1
fi
rm -rf "$BUNDLED_MODELS"
mkdir -p "$BUNDLED_SENSEVOICE"
cp "$MODEL_SOURCE/model.onnx" "$BUNDLED_SENSEVOICE/model.onnx"
cp "$MODEL_SOURCE/tokens.txt" "$BUNDLED_SENSEVOICE/tokens.txt"
mkdir -p "$BUNDLED_VAD"
cp "$VAD_SOURCE" "$BUNDLED_VAD/silero_vad.onnx"

ICON_SOURCE="$ROOT/assets/TypeSpeakerIcon.png"
ICONSET="$CONTENTS/Resources/TypeWhale.iconset"
if [[ -f "$ICON_SOURCE" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    size="${spec%% *}"
    name="${spec#* }"
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/$name" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/TypeWhale.icns"
  rm -rf "$ICONSET"
fi

xcrun clang \
  -O2 \
  -target arm64-apple-macosx14.0 \
  -I "$SHERPA_ROOT/include" \
  -c "$ROOT/native/TypeSpeakerNativeASR.c" \
  -o "$NATIVE_ASR_OBJECT"

# Earliest-possible, dependency-free launch/crash probe (pure POSIX). Linked into
# the executable so the Swift CrashReporter can funnel output through it.
xcrun clang \
  -O2 \
  -target arm64-apple-macosx14.0 \
  -c "$ROOT/native/LaunchProbe.c" \
  -o "$LAUNCH_PROBE_OBJECT"

swift_sources=("$ROOT/native/TypeSpeakerApp.swift")
if [[ -d "$ROOT/native/Sources" ]]; then
  while IFS= read -r source_file; do
    swift_sources+=("$source_file")
  done < <(find "$ROOT/native/Sources" -name '*.swift' -type f | sort)
fi

xcrun swiftc \
  -O \
  -target arm64-apple-macosx14.0 \
  -import-objc-header "$ROOT/native/TypeSpeakerNativeASR.h" \
  -framework AppKit \
  -framework AVFoundation \
  -framework ApplicationServices \
  -framework CryptoKit \
  -framework QuartzCore \
  -framework Security \
  -framework ServiceManagement \
  "${swift_sources[@]}" \
  "$NATIVE_ASR_OBJECT" \
  "$LAUNCH_PROBE_OBJECT" \
  -L "$NATIVE_ASR_LIB" \
  -l sherpa-onnx-c-api \
  -Xlinker -rpath \
  -Xlinker @executable_path/../Resources/NativeASR/lib \
  -o "$CONTENTS/MacOS/TypeWhale"
rm -f "$NATIVE_ASR_OBJECT" "$LAUNCH_PROBE_OBJECT"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
<key>CFBundleDisplayName</key><string>TypeWhale</string>
<key>CFBundleExecutable</key><string>TypeWhale</string>
<key>CFBundleIconFile</key><string>TypeWhale.icns</string>
<key>CFBundleIdentifier</key><string>com.waykingah.typewhale</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>TypeWhale</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3.10</string>
<key>CFBundleVersion</key><string>218</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>TypeWhale 需要使用麦克风进行本地语音转文字。</string>
</dict></plist>
PLIST

if [[ "${TYPESPEAKER_RELEASE:-0}" == "1" ]]; then
  SIGN_IDENTITY="${TYPESPEAKER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "Release builds require a Developer ID Application signing identity." >&2
    exit 1
  fi
else
  SIGN_IDENTITY="${TYPESPEAKER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    echo "Warning: using ad-hoc signing for a local development build." >&2
  fi
fi

for RUNTIME_DIR in "$NATIVE_ASR_LIB"; do
if [[ -d "$RUNTIME_DIR" ]]; then
  while IFS= read -r file; do
    if file "$file" | grep -q 'Mach-O'; then
      if ! codesign --verify --strict "$file" >/dev/null 2>&1; then
        codesign --force --sign "$SIGN_IDENTITY" "$file"
      fi
    fi
  done < <(find "$RUNTIME_DIR" -type f)
fi
done

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
if ! codesign --verify --deep --strict "$APP"; then
  if [[ "${TYPESPEAKER_RELEASE:-0}" == "1" ]]; then
    echo "Release signing verification failed." >&2
    exit 1
  fi
  echo "Warning: local development signature is not trusted for distribution." >&2
fi

if [[ "${TYPESPEAKER_SKIP_INSTALL:-0}" != "1" ]]; then
  INSTALL_APP_PATH="${TYPESPEAKER_INSTALL_APP_PATH:-/Applications/TypeWhale.app}"
  osascript -e 'tell application id "com.waykingah.typewhale" to quit' >/dev/null 2>&1 || true
  pkill -x -u "$(id -u)" TypeWhale >/dev/null 2>&1 || true
  sleep 0.5
  rm -rf "$INSTALL_APP_PATH"
  ditto "$APP" "$INSTALL_APP_PATH"
  xattr -dr com.apple.quarantine "$INSTALL_APP_PATH" >/dev/null 2>&1 || true
  codesign --verify --deep --strict "$INSTALL_APP_PATH"
  echo "$INSTALL_APP_PATH"
fi

echo "$APP"
