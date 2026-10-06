#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIO_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --audio)
      AUDIO_PATH="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$AUDIO_PATH" || ! -f "$AUDIO_PATH" ]]; then
  echo "Usage: $0 --audio /absolute/path/to/recording.wav" >&2
  exit 64
fi

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-prompt-replay.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
OUTPUT_DIR="$ROOT/.artifacts/smart-rewrite-prompt-replay/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

xcrun swiftc \
  -O \
  -parse-as-library \
  -framework AppKit \
  "$ROOT/native/Sources/Core/AppBrand.swift" \
  "$ROOT/native/Sources/Core/SmartInput/"*.swift \
  "$ROOT/native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift" \
  "$ROOT/native/Tests/SmartRewritePromptReplayCheck.swift" \
  -o "$BUILD_DIR/SmartRewritePromptReplayCheck"

"$BUILD_DIR/SmartRewritePromptReplayCheck" \
  --audio "$AUDIO_PATH" \
  --repo-root "$ROOT" \
  --output-dir "$OUTPUT_DIR"
