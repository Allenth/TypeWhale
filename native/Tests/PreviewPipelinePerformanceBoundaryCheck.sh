#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift"
AUDIO_SOURCE="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"
STATE_SOURCE="$ROOT/native/Sources/Application/SpeechInputState.swift"
COORDINATOR_SOURCE="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
COORDINATOR_SOURCE="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

required_patterns=(
  'enqueuedUptime: ProcessInfo.processInfo.systemUptime'
  'preview_request_start lane='
  'queue_ms='
  'preview_request_done lane='
  'recognition_ms='
  'total_ms='
  'audio_ms='
  'pending_fast='
  'correction_backlog='
  'preview_fast_budget_miss'
  'preview_correction_backlog_warning'
  'audioRange: PreviewAudioRange(start: 0, end: request.audioDuration)'
  'LaunchDiagnostics.markAsync('
)

for pattern in "${required_patterns[@]}"; do
  if ! rg -Fq "$pattern" "$SOURCE"; then
    echo "Missing preview performance boundary: $pattern" >&2
    exit 1
  fi
done

if rg -q 'LaunchDiagnostics\.mark\(' "$SOURCE"; then
  echo "Preview performance diagnostics must not synchronously write files from the main actor." >&2
  exit 1
fi

if ! rg -Uq 'LaunchDiagnostics\.markAsync\(\s*"experimental_preview_update' "$COORDINATOR_SOURCE"; then
  echo "Experimental preview state diagnostics must use the asynchronous logger." >&2
  exit 1
fi

if ! rg -Uq 'LaunchDiagnostics\.markAsync\([[:space:]]*"experimental_preview_update' "$COORDINATOR_SOURCE"; then
  echo "Experimental preview state updates must not synchronously write diagnostics from the main actor." >&2
  exit 1
fi

if ! rg -Fq 'audioDuration: TimeInterval' "$STATE_SOURCE"; then
  echo "Realtime snapshot requests must carry their captured audio duration." >&2
  exit 1
fi

if ! rg -Fq 'let audioDuration = Double(buffers.reduce' "$AUDIO_SOURCE"; then
  echo "AudioRecorder must calculate snapshot duration before dispatching it." >&2
  exit 1
fi

request_count=$(rg -c 'PreviewPipelineRequest\(' "$SOURCE")
uptime_count=$(rg -c 'enqueuedUptime: ProcessInfo\.processInfo\.systemUptime' "$SOURCE")
if [[ "$request_count" -ne "$uptime_count" ]]; then
  echo "Every preview request lane must capture monotonic enqueue uptime explicitly." >&2
  exit 1
fi

if rg -q 'Date\(\)|Date\(\)\.timeIntervalSince' "$SOURCE"; then
  echo "Preview performance durations must use monotonic uptime, not wall-clock Date." >&2
  exit 1
fi

echo "PreviewPipelinePerformanceBoundaryCheck passed"
