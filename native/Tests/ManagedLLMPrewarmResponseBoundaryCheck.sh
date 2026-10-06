#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

require_text() {
  local needle="$1"
  local message="$2"
  if ! grep -Fq "$needle" "$SPEECH"; then
    echo "$message" >&2
    exit 1
  fi
}

require_text 'try ManagedLLMResponseValidator.validate(response, requireFinalText: false)' \
  'Warmup must validate response.ok before reporting success.'
require_text 'try ManagedLLMResponseValidator.validate(prefillResponse, requireFinalText: true)' \
  'Prefill must validate response.ok and non-empty generation before reporting success.'
require_text 'managed_mlx warmup_failed' \
  'Warmup rejection must be logged as warmup_failed.'
require_text 'managed_mlx prefill_failed' \
  'Prefill rejection must be logged as prefill_failed.'

warmup_validate_line="$(rg -n -F 'try ManagedLLMResponseValidator.validate(response, requireFinalText: false)' "$SPEECH" | cut -d: -f1)"
warmup_done_line="$(rg -n -F 'managed_mlx warmup_done' "$SPEECH" | cut -d: -f1)"
prefill_validate_line="$(rg -n -F 'try ManagedLLMResponseValidator.validate(prefillResponse, requireFinalText: true)' "$SPEECH" | cut -d: -f1)"
prefill_done_line="$(rg -n -F 'managed_mlx prefill_done' "$SPEECH" | cut -d: -f1)"

test "$warmup_validate_line" -lt "$warmup_done_line"
test "$prefill_validate_line" -lt "$prefill_done_line"

echo "ManagedLLMPrewarmResponseBoundaryCheck passed"
