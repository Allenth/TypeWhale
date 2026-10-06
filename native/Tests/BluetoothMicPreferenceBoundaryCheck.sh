#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

require() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! rg -q "$pattern" "$ROOT/$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

require "preferBuiltInMicForBluetoothAudio" "native/Sources/Infrastructure/Settings/AppSettings.swift" "setting must be persisted in AppSettings"
require "preferBuiltInMicForBluetoothAudio" "native/Sources/Presentation/Main/MainViewController.swift" "main UI must expose a switch for the preference"
require "蓝牙耳机播放时使用 Mac 麦克风" "native/Sources/Presentation/Main/MainViewController+PanelLayout.swift" "voice page must show the standalone Bluetooth mic preference"
require "inspectorGroup\\(\"麦克风\"" "native/Sources/Presentation/Main/MainViewController+PanelLayout.swift" "voice page must put microphone settings in their own section"
require "preferBuiltInMicForBluetoothSystemDefault: controller\\.preferBuiltInMicForBluetoothAudioEnabled" "native/Sources/Application/SpeechInputCoordinator.swift" "recording start must pass the preference into route resolution"
require "preferredBuiltIn" "native/Sources/Application/SpeechInputCoordinator.swift" "recording switch path must support the preferred built-in mic resolution"

echo "BluetoothMicPreferenceBoundaryCheck passed"
