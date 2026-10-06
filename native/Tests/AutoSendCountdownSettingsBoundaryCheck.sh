#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"

grep -Fq 'let autoSendCountdownSeconds = NSStepper()' "$MAIN"
grep -Fq 'let autoSendCountdownValueLabel = NSTextField(labelWithString: "2 秒")' "$MAIN"
grep -Fq 'autoSendCountdownSeconds.minValue = 1' "$CONFIG"
grep -Fq 'autoSendCountdownSeconds.maxValue = 10' "$CONFIG"
grep -Fq 'autoSendCountdownSeconds.increment = 1' "$CONFIG"
grep -Fq 'autoSendCountdownSeconds.setAccessibilityLabel("自动发送倒计时")' "$CONFIG"
grep -Fq 'optionRow("发送倒计时", autoSendCountdownControl)' "$LAYOUT"
grep -Fq '@objc func saveAutoSendCountdownSeconds()' "$ACTIONS"
grep -Fq 'configuration.countdownSeconds = seconds' "$ACTIONS"
grep -Fq '自动发送倒计时已设为 \(seconds) 秒' "$ACTIONS"

echo "AutoSendCountdownSettingsBoundaryCheck passed"
