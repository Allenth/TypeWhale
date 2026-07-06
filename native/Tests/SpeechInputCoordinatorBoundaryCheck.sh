#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
STATE="$ROOT/native/Sources/Application/SpeechInputState.swift"

if ! grep -q "let channel: SpeechInputChannel" "$STATE"; then
  echo "SpeechSession must remember which input channel started the recording" >&2
  exit 1
fi

if ! grep -q "matchesTrigger(channel: SpeechInputChannel, purpose: SpeechInputPurpose)" "$STATE"; then
  echo "SpeechSession must expose same-trigger matching for hotkey up isolation" >&2
  exit 1
fi

if ! grep -q "submittedTaskIDs" "$ROOT/native/Sources/Application/SpeechWorkflowState.swift"; then
  echo "SpeechWorkflowState must keep multiple submitted tasks so a new recording does not stale an older background result" >&2
  exit 1
fi

hotkey_up_block="$(
  awk '
    /private func handleHotkeyUp\(channel: SpeechInputChannel, purpose: SpeechInputPurpose, binding: HotkeyBinding\)/ { in_block=1 }
    in_block { print }
    in_block && /^    }$/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "shouldReplaceActiveRecording(channel: channel, purpose: purpose)" <<<"$hotkey_up_block"; then
  echo "Hotkey up must decide whether it is replacing the active recording with a new one" >&2
  exit 1
fi

if ! grep -q "if shouldStartReplacement" <<<"$hotkey_up_block"; then
  echo "A different recording shortcut key-up must finish the old recording and immediately start the new one" >&2
  exit 1
fi

hotkey_down_block="$(
  awk '
    /private func handleHotkeyDown\(channel: SpeechInputChannel, purpose: SpeechInputPurpose, binding: HotkeyBinding\)/ { in_block=1 }
    in_block { print }
    in_block && /private func handleHotkeyUp/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "if let activeSession" <<<"$hotkey_down_block"; then
  echo "Hotkey down must handle an already active recording instead of ignoring it" >&2
  exit 1
fi

if ! grep -q "activeSession.matchesTrigger(channel: channel, purpose: purpose)" <<<"$hotkey_down_block"; then
  echo "Same recording shortcut key-down must leave finish handling to key-up: 我开、我关" >&2
  exit 1
fi

if ! grep -q "suppressNextHotkeyUp = true" <<<"$hotkey_down_block"; then
  echo "Replacement recording started on key-down must suppress the paired key-up: 我开、他开；先关我，再开他" >&2
  exit 1
fi

non_media_active_block="$(
  awk '
    /let displayName = binding.displayName/ { in_block=1 }
    in_block { print }
    in_block && /guard !recorder.isRecording/ { exit }
  ' "$SPEECH"
)"

same_trigger_line="$(grep -n "activeSession.matchesTrigger(channel: channel, purpose: purpose)" <<<"$non_media_active_block" | head -n 1 | cut -d: -f1)"
finish_line="$(grep -n "finishRecording()" <<<"$non_media_active_block" | head -n 1 | cut -d: -f1)"

if [[ -z "$same_trigger_line" || -z "$finish_line" || "$same_trigger_line" -ge "$finish_line" ]]; then
  echo "Non-media same-trigger key-down must be checked before finishRecording, otherwise key-up can reopen the capsule" >&2
  exit 1
fi

echo "SpeechInputCoordinatorBoundaryCheck passed"
