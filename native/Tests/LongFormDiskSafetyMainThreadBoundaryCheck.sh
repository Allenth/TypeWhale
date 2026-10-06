#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

if ! rg -q 'longFormDiskSafetyQueue\.async' "$SOURCE"; then
  echo "Long-form disk capacity lookup must run on the utility queue, not the main actor." >&2
  exit 1
fi

if rg -q 'if enforceLongFormDiskSafety\(\)' "$SOURCE"; then
  echo "Audio-band callbacks must not synchronously enforce long-form disk safety." >&2
  exit 1
fi

if ! rg -q 'longFormDiskSafetyProbeGate\.beginIfDue' "$SOURCE"; then
  echo "Long-form disk probes must be rate-limited before leaving the main actor." >&2
  exit 1
fi

echo "LongFormDiskSafetyMainThreadBoundaryCheck passed"
