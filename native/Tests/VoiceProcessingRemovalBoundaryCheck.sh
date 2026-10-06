#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

forbidden_patterns=(
  "micNoiseReduction"
  "micVoiceProcessingEnabled"
  "micVoiceProcessing"
  "voiceProcessingEnabled"
  "setVoiceProcessingEnabled"
  "麦克风降噪"
  "语音增强"
)

for pattern in "${forbidden_patterns[@]}"; do
  if rg -n "$pattern" \
    "$ROOT/native/Sources/Application" \
    "$ROOT/native/Sources/Infrastructure/Audio" \
    "$ROOT/native/Sources/Infrastructure/Settings" \
    "$ROOT/native/Sources/Presentation/Main"; then
    echo "Voice processing feature must be removed from production sources: $pattern" >&2
    exit 1
  fi
done

echo "VoiceProcessingRemovalBoundaryCheck passed"
