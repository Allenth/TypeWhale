#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

property_count="$(grep -Fc 'private let systemMediaPlaybackController = SystemMediaPlaybackController()' "$SPEECH" || true)"
pause_count="$(grep -Fc 'systemMediaPlaybackController.pauseIfNeeded(' "$SPEECH" || true)"
resume_count="$(grep -Fc 'systemMediaPlaybackController.resume()' "$SPEECH" || true)"

if [[ "$property_count" -ne 1 ]]; then
  echo "SpeechInputCoordinator must own exactly one system media controller" >&2
  exit 1
fi
if [[ "$pause_count" -ne 1 ]]; then
  echo "Recording start must request media pause exactly once" >&2
  exit 1
fi
if [[ "$resume_count" -ne 1 ]]; then
  echo "Unified recording cleanup must request media resume exactly once" >&2
  exit 1
fi

start_block="$(sed -n '1488,1508p' "$SPEECH")"
if ! grep -Fq 'enabled: controller.pauseSystemMediaWhileRecordingEnabled' <<<"$start_block"; then
  echo "Media pause must share the recording start boundary with volume ducking" >&2
  exit 1
fi
if ! grep -Fq 'outputAudioDucker.duckIfNeeded' <<<"$start_block"; then
  echo "Existing volume ducking must remain at the recording start boundary" >&2
  exit 1
fi

cleanup_block="$(
  awk '
    /private func clearActiveRecording\(/ { in_block=1 }
    in_block { print }
    in_block && /private func handleAudioInputRouteEvent/ { exit }
  ' "$SPEECH"
)"
if ! grep -Fq 'systemMediaPlaybackController.resume()' <<<"$cleanup_block" ||
   ! grep -Fq 'outputAudioDucker.restore()' <<<"$cleanup_block"; then
  echo "Media resume and volume restore must share unified recording cleanup" >&2
  exit 1
fi

echo "RecordingAudioPolicyCoordinatorBoundaryCheck passed"
