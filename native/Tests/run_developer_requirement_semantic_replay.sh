#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROUNDS=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rounds)
      ROUNDS="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

if ! [[ "$ROUNDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "--rounds must be a positive integer" >&2
  exit 64
fi

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-developer-replay.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
OUTPUT_DIR="$ROOT/.artifacts/developer-requirement-semantic-replay/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

xcrun swiftc \
  -O \
  -parse-as-library \
  -framework AppKit \
  "$ROOT/native/Sources/Core/AppBrand.swift" \
  "$ROOT/native/Sources/Core/SmartInput/"*.swift \
  "$ROOT/native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift" \
  "$ROOT/native/Tests/DeveloperRequirementSemanticReplayCheck.swift" \
  -o "$BUILD_DIR/DeveloperRequirementSemanticReplayCheck"

"$BUILD_DIR/DeveloperRequirementSemanticReplayCheck" \
  --repo-root "$ROOT" \
  --output-dir "$OUTPUT_DIR" \
  --rounds "$ROUNDS"
