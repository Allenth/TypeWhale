#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT/native/build_native_app.sh"
README="$ROOT/README.md"
MACOS_README="$ROOT/macos/README.md"
VERSION_HISTORY="$ROOT/native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift"
INSTALL_APP_PATH="${TYPESPEAKER_INSTALL_APP_PATH:-/Applications/TypeWhale.app}"

mode="full-version"
for arg in "$@"; do
  case "$arg" in
    --build-only) mode="build-only" ;;
    --full-version) mode="full-version" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ "${TYPEWHALE_BUILD_ONLY:-0}" == "1" ]]; then
  mode="build-only"
fi

current_version="$(perl -ne 'print "$1\n" if m{<key>CFBundleShortVersionString</key><string>([^<]+)}' "$BUILD_SCRIPT" | head -1)"
current_build="$(perl -ne 'print "$1\n" if m{<key>CFBundleVersion</key><string>([^<]+)}' "$BUILD_SCRIPT" | head -1)"

if [[ -z "$current_version" || -z "$current_build" ]]; then
  echo "Unable to read version/build from $BUILD_SCRIPT" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$current_version"
if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "Unexpected version format: $current_version" >&2
  exit 1
fi

next_patch=$((patch + 1))
next_build=$((current_build + 1))
if [[ -n "${TYPEWHALE_NEXT_VERSION:-}" ]]; then
  mode="full-version"
fi

if [[ "$mode" == "build-only" ]]; then
  next_version="$current_version"
else
  next_version="${TYPEWHALE_NEXT_VERSION:-${major}.${minor}.${next_patch}}"
fi

if [[ -n "${TYPEWHALE_NEXT_VERSION:-}" && ! "$TYPEWHALE_NEXT_VERSION" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
  echo "Unexpected TYPEWHALE_NEXT_VERSION format: $TYPEWHALE_NEXT_VERSION" >&2
  exit 1
fi

if [[ -f "$VERSION_HISTORY" ]] && ! grep -Fq "版本 $next_version (Build $next_build)" "$VERSION_HISTORY"; then
  cat >&2 <<EOF
Missing app version history entry for $next_version (Build $next_build).
Add it to:
  $VERSION_HISTORY

Every local release build changes the installed app version, so the in-app version history must explain why that build exists.
EOF
  exit 1
fi

if [[ "$next_version" != "$current_version" ]]; then
  perl -0pi -e "s{(<key>CFBundleShortVersionString</key><string>)\\Q$current_version\\E}{\${1}$next_version}" "$BUILD_SCRIPT"
fi
perl -0pi -e "s{(<key>CFBundleVersion</key><string>)\\Q$current_build\\E}{\${1}$next_build}" "$BUILD_SCRIPT"

if [[ -f "$README" ]]; then
  perl -0pi -e 's{Current local release build in this repository is `[^`]+`}{Current local release build in this repository is `'"$next_version ($next_build)"'`}' "$README"
  perl -0pi -e "s{dist/TypeWhale-[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+\\.dmg}{dist/TypeWhale-$next_version-$next_build.dmg}g" "$README"
fi

if [[ -f "$MACOS_README" ]]; then
  perl -0pi -e 's{当前本地发布版本：`[^`]+`}{当前本地发布版本：`'"$next_version ($next_build)"'`}' "$MACOS_README"
fi

if [[ "$mode" == "build-only" ]]; then
  echo "Bumped TypeWhale build to $next_version ($next_build)"
else
  echo "Bumped TypeWhale version to $next_version ($next_build)"
fi
"$BUILD_SCRIPT"
sleep 0.8
if ! open "$INSTALL_APP_PATH"; then
  sleep 1.2
  open -n "$INSTALL_APP_PATH"
fi

echo "Installed app version:"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL_APP_PATH/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$INSTALL_APP_PATH"
