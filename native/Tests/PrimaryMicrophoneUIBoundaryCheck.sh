#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'onPrimaryMicrophoneSelection' "$MAIN"
grep -Fq 'AudioInputDevice.selectedName' "$MAIN"
grep -Fq 'audioInputDeviceMode.menu?.delegate = self' "$CONFIG"
grep -Fq 'func menuWillOpen(_ menu: NSMenu)' "$CONFIG"
grep -Fq 'guard !audioInputDeviceMenuHasLoaded' "$CONFIG"
grep -Fq 'optionRow("主麦克风"' "$LAYOUT"
test "$(grep -o 'optionRow("主麦克风"\|inspectorGroup("主麦克风"' "$LAYOUT" | wc -l | tr -d ' ')" = "1"
! grep -Fq 'optionRow("输入设备"' "$LAYOUT"
grep -Fq '主麦克风已切换到' "$COORDINATOR"
grep -Fq '已断开，已改为跟随系统' "$COORDINATOR"
grep -Fq 'ToastPresenter.shared.show(message' "$COORDINATOR"
! grep -Fq 'popup.show(state: "正在切换麦克风' "$COORDINATOR"
! grep -Fq 'popup.show(state: "麦克风已切换' "$COORDINATOR"

echo "PrimaryMicrophoneUIBoundaryCheck passed"
