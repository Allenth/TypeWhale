#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

if ! grep -q "struct PendingOpenClawMessage" "$SPEECH"; then
  echo "SpeechInputCoordinator must keep recognized OpenClaw messages in a serial queue." >&2
  exit 1
fi

if ! awk '
  /struct PendingOpenClawMessage/ { in_block=1 }
  in_block && /let turnID: UUID/ { found=1 }
  in_block && /^    }/ { exit }
  END { exit found ? 0 : 1 }
' "$SPEECH"; then
  echo "Queued OpenClaw messages must carry a turnID so replies, loading, and returned events stay attached to the right user message." >&2
  exit 1
fi

if ! grep -q "private var pendingOpenClawMessages: \\[PendingOpenClawMessage\\]" "$SPEECH" ||
   ! grep -q "private var openClawSendInFlight = false" "$SPEECH"; then
  echo "SpeechInputCoordinator must track queued and in-flight OpenClaw sends separately from recording state." >&2
  exit 1
fi

openclaw_toggle_block="$(
  awk '
    /private func activateOpenClawRecording\(channel: SpeechInputChannel, binding: HotkeyBinding\)/ { in_block=1 }
    in_block { print }
    in_block && /private func toggleAutoTranslateFromHotkey/ { exit }
  ' "$SPEECH"
)"

if grep -q "openClawRequestInProgress()" <<<"$openclaw_toggle_block" ||
   grep -q "openclaw_toggle_ignored reason=request_in_progress" <<<"$openclaw_toggle_block"; then
  echo "OpenClaw activation must not be ignored while a previous OpenClaw request is waiting for a reply." >&2
  exit 1
fi

if ! grep -Fq 'purpose=\(purpose.logName)' "$SPEECH"; then
  echo "Recording diagnostics must include purpose so OpenClaw-vs-dictation routing mistakes can be investigated from logs." >&2
  exit 1
fi

finish_block="$(
  awk '
    /private func finishRecording/ { in_block=1 }
    in_block { print }
    in_block && /private func startFinalRecognition/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "if purpose == \\.openClawChat" <<<"$finish_block" ||
   ! grep -q "popup.hideAnimated()" <<<"$finish_block" ||
   ! grep -q "popup.show(state: \"检测中\")" <<<"$finish_block"; then
  echo "Finishing an OpenClaw recording must hide the recording capsule instead of keeping the generic detection capsule visible." >&2
  exit 1
fi

recognition_block="$(
  awk '
    /private func startFinalRecognition/ { in_block=1 }
    in_block { print }
    in_block && /let request = FinalRecognitionRequest/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "task.purpose != \\.openClawChat" <<<"$recognition_block"; then
  echo "OpenClaw final recognition must not reopen the capsule with the generic recognition state." >&2
  exit 1
fi

openclaw_result_block="$(
  awk '
    /private func submitOpenClawRequest/ { in_block=1 }
    in_block { print }
    in_block && /private func smartRewritePreference/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "enqueueOpenClawMessage" <<<"$openclaw_result_block" ||
   ! grep -q "finishFinalTask(task)" <<<"$openclaw_result_block"; then
  echo "OpenClaw recognition completion must enqueue the message and immediately release the recording state for the next utterance." >&2
  exit 1
fi

if grep -q "popup.show" <<<"$openclaw_result_block"; then
  echo "OpenClaw send/reply handling must not reopen the recording capsule; replies belong in the OpenClaw reply stack." >&2
  exit 1
fi

openclaw_queue_block="$(
  awk '
    /private func drainNextOpenClawMessageIfNeeded/ { in_block=1 }
    in_block { print }
    in_block && /private func smartRewritePreference/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "openClawSendInFlight = true" <<<"$openclaw_queue_block" ||
   ! grep -q "pendingOpenClawMessages.removeFirst()" <<<"$openclaw_queue_block" ||
   ! grep -q "turnID: message.turnID" <<<"$openclaw_queue_block" ||
   ! grep -q "drainNextOpenClawMessageIfNeeded()" <<<"$openclaw_queue_block"; then
  echo "OpenClaw queue must send one message at a time, keep reply UI scoped to the message turn, and drain the next queued message after completion." >&2
  exit 1
fi

echo "OpenClawCapsuleDismissalSourceCheck passed"
