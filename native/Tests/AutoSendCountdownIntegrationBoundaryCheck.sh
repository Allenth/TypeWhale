#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
paste="$ROOT/native/Sources/Infrastructure/Paste/PasteCoordinator.swift"
speech="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
hotkey="$ROOT/native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift"
emitter="$ROOT/native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift"
presenter="$ROOT/native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift"

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if rg -q "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_pattern \
  'postPasteActionScheduler\.schedule' \
  "$paste" \
  "PasteCoordinator must submit post-paste actions to the countdown scheduler"
require_pattern \
  'taskID:' \
  "$paste" \
  "Paste requests must retain their task ID"
require_pattern \
  'autoSendCountdownCoordinator\.cancel\(reason: \.newRecording\)' \
  "$speech" \
  "Starting a new recording must cancel an old countdown"
require_pattern \
  'hotkey\.onEscape' \
  "$speech" \
  "SpeechInputCoordinator must connect Esc cancellation"
require_pattern \
  'hotkey\.onManualSubmitKey' \
  "$speech" \
  "SpeechInputCoordinator must connect manual Return cancellation"
require_pattern \
  'reason: \.manualSubmitKey' \
  "$speech" \
  "Manual Return must terminate the active countdown"
if ! rg -Uq \
  'presenter: AutoSendCountdownPresenter\(\s*capsuleFrame: \{ \[weak self\] in\s*self\?\.popup\.presentationFrame\s*\}\s*\)' \
  "$speech"; then
  echo "The countdown presenter must read the current production capsule frame" >&2
  exit 1
fi
require_pattern \
  'escapeCancellationGate\.handle' \
  "$hotkey" \
  "HotkeyMonitor must consume the paired Esc down/up through the domain gate"
require_pattern \
  'AutoSendManualSubmitGate\.shouldCancelCountdown' \
  "$hotkey" \
  "HotkeyMonitor must observe physical Return without consuming it"
require_pattern \
  'eventSourceUserData' \
  "$emitter" \
  "TypeWhale-generated Return events must carry an identity marker"
require_pattern \
  'syntheticEventUserData' \
  "$emitter" \
  "The emitter must use the same marker that the manual-submit gate ignores"

reject_pattern \
  'postPasteActionDelay' \
  "$paste" \
  "The old immediate post-paste delay must be removed"
reject_pattern \
  'asyncAfter.*1\.5' \
  "$paste" \
  "PasteCoordinator must not wait for the countdown"
reject_pattern \
  'AutoSendCountdownPresenter' \
  "$paste" \
  "PasteCoordinator must not own Presentation"
reject_pattern \
  'UserDefaults|AutoSendSettingsStore' \
  "$paste" \
  "PasteCoordinator must not read settings"
reject_pattern \
  'PostPasteKeyEmitter|SystemPostPasteKeyEmitter' \
  "$presenter" \
  "Presenter must not emit system keys"
reject_pattern \
  'PasteCoordinator' \
  "$presenter" \
  "Presenter must not own the paste queue"

if rg -n 'PostPasteKeyEmitter|SystemPostPasteKeyEmitter' \
  "$ROOT/native/Sources/Presentation"; then
  echo "Presentation must never emit post-paste system keys" >&2
  exit 1
fi

echo "AutoSendCountdownIntegrationBoundaryCheck passed"
