#!/bin/zsh
# 把当前已构建的 macos/TypeWhale.app 打成可分发 DMG 到 dist/。
# 由 build_and_log.sh 按节奏或显式触发；也可单独运行。
# 注意：此脚本只做打包，不做 Developer ID 公证（notarization 见 docs/商业化路线图.md P0）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/macos/TypeWhale.app"
BUILD_SCRIPT="$ROOT/native/build_native_app.sh"
DIST="$ROOT/dist"

if [[ ! -d "$APP" ]]; then
  echo "未找到已构建的 App：$APP（请先运行构建）" >&2
  exit 1
fi

ver="$(perl -ne 'print "$1" if m{<key>CFBundleShortVersionString</key><string>([^<]+)}' "$BUILD_SCRIPT" | head -1)"
bld="$(perl -ne 'print "$1" if m{<key>CFBundleVersion</key><string>([^<]+)}' "$BUILD_SCRIPT" | head -1)"
if [[ -z "$ver" || -z "$bld" ]]; then
  echo "无法从 $BUILD_SCRIPT 读取版本号" >&2
  exit 1
fi

mkdir -p "$DIST"
DMG="$DIST/TypeWhale-$ver-$bld.dmg"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$APP" "$staging/TypeWhale.app"
ln -s /Applications "$staging/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "TypeWhale $ver" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

# 只把 DMG 路径打到 stdout，方便调用方捕获；其余信息走 stderr。
echo "已生成 DMG：$DMG（$(du -h "$DMG" | awk '{print $1}')）" >&2
echo "$DMG"
