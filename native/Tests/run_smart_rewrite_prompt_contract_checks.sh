#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-prompt-contracts.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

COMMON_SOURCES=(
  "$ROOT/native/Sources/Core/SmartInput/RewriteProfile.swift"
  "$ROOT/native/Sources/Core/SmartInput/DeveloperLexicon.swift"
  "$ROOT/native/Sources/Core/SmartInput/DeveloperLexiconStore.swift"
  "$ROOT/native/Sources/Core/SmartInput/DeveloperTermNormalizer.swift"
  "$ROOT/native/Sources/Core/SmartInput/SmartRewriteOutputSanitizer.swift"
  "$ROOT/native/Sources/Core/SmartInput/SmartRewritePromptStore.swift"
  "$ROOT/native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift"
  "$ROOT/native/Tests/SmartRewritePromptTestSupport.swift"
)

for test_name in DeveloperTermNormalizerCheck SmartRewritePromptCheck PromptFixtureCheck; do
  test_binary="$TEST_DIR/$test_name"
  xcrun swiftc \
    -Onone \
    -parse-as-library \
    "${COMMON_SOURCES[@]}" \
    "$ROOT/native/Tests/$test_name.swift" \
    -o "$test_binary"
  "$test_binary"
done
