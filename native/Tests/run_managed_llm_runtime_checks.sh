#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-managed-llm.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

COMMON_SOURCES=(
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift"
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift"
)

xcrun swiftc \
  -Onone \
  -parse-as-library \
  "${COMMON_SOURCES[@]}" \
  "$ROOT/native/Tests/ManagedMLXLLMRuntimeCheck.swift" \
  -o "$TEST_DIR/ManagedMLXLLMRuntimeCheck"
"$TEST_DIR/ManagedMLXLLMRuntimeCheck"

xcrun swiftc \
  -Onone \
  -parse-as-library \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedLLMResponseValidator.swift" \
  "$ROOT/native/Tests/ManagedLLMResponseValidatorCheck.swift" \
  -o "$TEST_DIR/ManagedLLMResponseValidatorCheck"
"$TEST_DIR/ManagedLLMResponseValidatorCheck"
