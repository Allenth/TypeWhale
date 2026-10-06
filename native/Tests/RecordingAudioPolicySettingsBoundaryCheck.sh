#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SETTINGS="$ROOT/native/Sources/Infrastructure/Settings/AppSettings.swift"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
CONFIGURATION="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"

require_text() {
  local file="$1"
  local text="$2"
  local message="$3"
  if ! grep -Fq "$text" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_text "$SETTINGS" 'var pauseSystemMediaWhileRecordingEnabled: Bool' \
  'MainViewSettings must expose the media pause preference'
require_text "$SETTINGS" 'private static let pauseSystemMediaWhileRecordingKey = "pauseSystemMediaWhileRecording"' \
  'AppSettingsStore must own a dedicated media pause key'
require_text "$SETTINGS" 'pauseSystemMediaWhileRecordingEnabled: UserDefaults.standard.bool(forKey: pauseSystemMediaWhileRecordingKey)' \
  'AppSettingsStore must load media pause independently with a false default'
require_text "$SETTINGS" 'UserDefaults.standard.set(settings.pauseSystemMediaWhileRecordingEnabled, forKey: pauseSystemMediaWhileRecordingKey)' \
  'AppSettingsStore must persist media pause independently'
require_text "$MAIN" 'let pauseSystemMedia = BrandSwitch()' \
  'MainViewController must own a media pause switch'
require_text "$MAIN" 'pauseSystemMedia.state = settings.pauseSystemMediaWhileRecordingEnabled ? .on : .off' \
  'MainViewController must restore the media pause switch state'
require_text "$ACTIONS" 'pauseSystemMediaWhileRecordingEnabled: pauseSystemMedia.state == .on' \
  'saveSettings must persist the media pause switch'
require_text "$ACTIONS" 'var pauseSystemMediaWhileRecordingEnabled: Bool' \
  'SpeechInputCoordinator must read the media pause switch through a computed property'
require_text "$CONFIGURATION" 'pauseSystemMedia.setAccessibilityLabel("录音时暂停媒体")' \
  'The media pause switch must have an accessibility label'
require_text "$CONFIGURATION" 'pauseSystemMedia.toolTip = "录音开始时仅暂停正在播放的系统媒体；录音结束后只恢复本次暂停的内容。"' \
  'The media pause switch must disclose state-aware ownership semantics'
require_text "$LAYOUT" 'optionRow("录音时暂停媒体", pauseSystemMedia)' \
  'Recording settings must display the independent media pause row'

echo "RecordingAudioPolicySettingsBoundaryCheck passed"
