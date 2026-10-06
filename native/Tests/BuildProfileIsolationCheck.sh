#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/native/build_native_app.sh"
RELEASE="$ROOT/native/release_local_build.sh"

grep -q 'APP_DISPLAY_NAME="${TYPEWHALE_APP_DISPLAY_NAME:-TypeWhale Pro}"' "$BUILD"
grep -q 'APP_EXECUTABLE="${TYPEWHALE_APP_EXECUTABLE:-TypeWhalePro}"' "$BUILD"
grep -q 'APP_BUNDLE_IDENTIFIER="${TYPEWHALE_APP_BUNDLE_IDENTIFIER:-com.waykingah.typewhale.pro}"' "$BUILD"
grep -q 'APP_BUNDLE_NAME="$APP_DISPLAY_NAME.app"' "$BUILD"
grep -q 'CFBundleDisplayName</key><string>$APP_DISPLAY_NAME' "$BUILD"
grep -q 'CFBundleExecutable</key><string>$APP_EXECUTABLE' "$BUILD"
grep -q 'CFBundleIdentifier</key><string>$APP_BUNDLE_IDENTIFIER' "$BUILD"
grep -q 'CFBundleName</key><string>$APP_DISPLAY_NAME' "$BUILD"
grep -q 'INSTALL_APP_PATH="${TYPESPEAKER_INSTALL_APP_PATH:-/Applications/$APP_BUNDLE_NAME}"' "$BUILD"
grep -q 'tell application id \\"$APP_BUNDLE_IDENTIFIER\\" to quit' "$BUILD"
grep -q 'pkill -x -u "$(id -u)" "$APP_EXECUTABLE"' "$BUILD"

grep -q 'APP_DISPLAY_NAME="${TYPEWHALE_APP_DISPLAY_NAME:-TypeWhale Pro}"' "$RELEASE"
grep -q 'APP_BUNDLE_NAME="$APP_DISPLAY_NAME.app"' "$RELEASE"
grep -q 'INSTALL_APP_PATH="${TYPESPEAKER_INSTALL_APP_PATH:-/Applications/$APP_BUNDLE_NAME}"' "$RELEASE"
grep -q 'open "$INSTALL_APP_PATH"' "$RELEASE"

if TYPEWHALE_APP_DISPLAY_NAME="TypeWhale Pro TTS Native" \
   TYPEWHALE_APP_EXECUTABLE="TypeWhaleProTTSNative" \
   TYPEWHALE_APP_BUNDLE_IDENTIFIER="com.waykingah.typewhale.pro.tts-native" \
   TYPESPEAKER_INSTALL_APP_PATH="/Applications/TypeWhale Pro TTS Native.app" \
   zsh -n "$BUILD" && zsh -n "$RELEASE"; then
  :
else
  echo "Build scripts must remain syntactically valid with isolated app profile overrides." >&2
  exit 1
fi

echo "BuildProfileIsolationCheck passed"
