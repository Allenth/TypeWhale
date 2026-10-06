#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

file=native/Sources/Infrastructure/Applications/ApplicationCatalog.swift

if rg -n \
  'Timer|SpeechSession|AudioRecorder|RealtimePreview|TranscriptionProvider|NSWorkspace.*icon' \
  "$file"; then
  echo "ApplicationCatalog crossed runtime, realtime, or icon-loading boundary" >&2
  exit 1
fi

if ! rg -q 'Task\.detached\(priority: \.utility\)' "$file"; then
  echo "ApplicationCatalog must scan on a detached utility task" >&2
  exit 1
fi

if ! rg -q 'Task\.isCancelled' "$file"; then
  echo "ApplicationCatalog scan must cooperate with cancellation" >&2
  exit 1
fi

echo "ApplicationCatalogRuntimeBoundaryCheck passed"
