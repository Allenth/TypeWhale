#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-model-health.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc \
  -Onone \
  -parse-as-library \
  "$ROOT/native/Sources/Core/SmartInput/SmartAIModel.swift" \
  "$ROOT/native/Sources/Core/SmartInput/ManagedLLMSelection.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedLLMResponseValidator.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXRuntimeLocator.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedLLMModelCatalog.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/LocalModelHealthCheckService.swift" \
  "$ROOT/native/Tests/LocalModelHealthCheckServiceCheck.swift" \
  -o "$TEST_DIR/LocalModelHealthCheckServiceCheck"

"$TEST_DIR/LocalModelHealthCheckServiceCheck"
