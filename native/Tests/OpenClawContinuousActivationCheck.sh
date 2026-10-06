#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

finish_block="$(
  awk '
    /private func finishRecording/ { in_block=1 }
    in_block { print }
    in_block && /private func startFinalRecognition/ { exit }
  ' "$SPEECH"
)"

if grep -Fq 'longFormEnabled' <<<"$finish_block"; then
  echo "All recording purposes must bypass experimental long-form finalization and use full-audio recognition." >&2
  exit 1
fi

if grep -q 'longFormFinalizationTaskIDs.insert(taskID)' <<<"$finish_block" &&
   ! grep -q 'if longFormEnabled {' <<<"$finish_block"; then
  echo "Long-form finalization tracking must stay behind the longFormEnabled gate." >&2
  exit 1
fi

vad_failure_block="$(
  awk '
    /case \.failure\(let error\):/ { in_block=1 }
    in_block { print }
    in_block && /case \.success\(false\):/ { exit }
  ' <<<"$finish_block"
)"

if grep -q 'popup.show(state: "识别中"' <<<"$vad_failure_block" &&
   ! grep -Fq 'task.purpose != .openClawChat' <<<"$vad_failure_block"; then
  echo "OpenClaw VAD fallback must not reopen the generic recognition popup." >&2
  exit 1
fi
