#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"

save_block="$(
  awk '
    /@objc func saveSettings\(\)/ { in_block=1 }
    in_block { print }
    in_block && /@objc func saveOpenClawSettingsFromUI/ { exit }
  ' "$ACTIONS"
)"

if grep -Fq "realtime.state = .on" <<<"$save_block"; then
  echo "Pause auto-finish must not force realtime preview on" >&2
  exit 1
fi

if grep -Fq "autoFinish.state = .off" <<<"$save_block"; then
  echo "Turning realtime preview off must not turn pause auto-finish off" >&2
  exit 1
fi

if ! grep -Fq "realtimePreviewEnabled: realtime.state == .on" <<<"$save_block"; then
  echo "Realtime preview must still persist its own switch state" >&2
  exit 1
fi

if ! grep -Fq "autoFinishAfterPauseEnabled: autoFinish.state == .on" <<<"$save_block"; then
  echo "Pause auto-finish must still persist its own switch state" >&2
  exit 1
fi

echo "PauseAutoFinishSettingsBoundaryCheck passed"
