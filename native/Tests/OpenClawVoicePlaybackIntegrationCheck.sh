#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

grep -q 'OpenClawVoicePlayer.shared.speak(response.replyText)' "$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
grep -q 'OpenClawVoicePlayer.shared.prewarm()' "$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
grep -q 'OpenClawVoicePlaybackNotification.didStartSpeaking' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'OpenClawVoicePlaybackNotification.didStopSpeaking' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'stdoutReadHandle' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'stderrReadHandle' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
! grep -q 'readabilityHandler' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
! grep -q 'read(upToCount:' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'handle.availableData' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'markPipeClosed' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'resourceName = "tts_benchmark_worker"' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'speechSegments(from:' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'ZipVoiceTTSBackend' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q '"voiceID"' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
! grep -q 'MeloTTSVoiceBackend' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
! grep -q 'SherpaNativeTTSBackend' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'ensureBackend(settings:' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'stopActiveAudioPlayback()' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
if awk '
  /case \.stopPreviousAndPlayLatest:/ { in_block=1 }
  in_block { print }
  in_block && /case \.queueReplies:/ { exit }
' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift" | grep -q 'stopActiveProcesses()'; then
  echo "Speaking the latest OpenClaw reply must not stop the prewarmed TTS sidecar." >&2
  exit 1
fi
awk '
  /case \.stopPreviousAndPlayLatest:/ { in_block=1 }
  in_block { print }
  in_block && /case \.queueReplies:/ { exit }
' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift" | grep -q 'cancelActiveSynthesis()'
test -f "$ROOT/native/Resources/tts_benchmark_worker.py"
grep -q 'sherpa-zipvoice' "$ROOT/native/Resources/tts_benchmark_worker.py"
grep -q 'scheduleBackendIdleShutdown()' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'duringPlayback:' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'synthesizeNextPendingRequest()' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'buffer_wait_seconds=' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'for line in sys.stdin' "$ROOT/native/Resources/tts_benchmark_worker.py"
