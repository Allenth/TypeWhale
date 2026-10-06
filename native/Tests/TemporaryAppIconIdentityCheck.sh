#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/native/build_native_app.sh"
BRAND="$ROOT/native/Sources/Core/AppBrand.swift"
LIFECYCLE="$ROOT/native/Sources/Application/AppLifecycleCoordinator.swift"
PLAN="$ROOT/docs/superpowers/plans/2026-07-11-openclaw-sherpa-native-tts.md"

grep -q 'DEFAULT_ICON_SOURCE="$ROOT/assets/TypeWhaleAppIcon-ink.png"' "$BUILD"
grep -q 'TEMPORARY_PROFILE_ICON_SOURCE="$ROOT/assets/TypeWhaleAppIcon-origami.png"' "$BUILD"
grep -q 'TYPEWHALE_APP_ICON_SOURCE' "$BUILD"
grep -q 'APP_DISPLAY_NAME" != "TypeWhale Pro"' "$BUILD"
grep -q 'ICON_SOURCE="$TEMPORARY_PROFILE_ICON_SOURCE"' "$BUILD"

grep -q 'static let bundleIdentifier' "$BRAND"
grep -q 'static let temporaryTTSNativeBundleIdentifier = "com.waykingah.typewhale.pro.tts-native"' "$BRAND"
grep -q 'static var isTemporaryTTSNativeProfile: Bool' "$BRAND"

grep -q 'AppBrand.isTemporaryTTSNativeProfile' "$LIFECYCLE"
grep -q 'drawTemporaryProfileStatusBadge' "$LIFECYCLE"
grep -q 'TYPEWHALE_APP_ICON_SOURCE' "$PLAN"
grep -q 'status bar icon' "$PLAN"

echo "TemporaryAppIconIdentityCheck passed"
