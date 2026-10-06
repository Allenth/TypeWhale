#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-runtime-locator.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc \
  -Onone \
  -parse-as-library \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXRuntimeLocator.swift" \
  "$ROOT/native/Tests/ManagedMLXRuntimeLocatorCheck.swift" \
  -o "$TEST_DIR/ManagedMLXRuntimeLocatorCheck"

"$TEST_DIR/ManagedMLXRuntimeLocatorCheck"
