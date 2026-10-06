#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
PANEL="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
REMOTE_MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController+Remote.swift"
REMOTE_DIR="$ROOT/native/Sources/Presentation/Remote"

test -f "$REMOTE_MAIN"
test -f "$REMOTE_DIR/RemoteInspectorView.swift"
test -f "$REMOTE_DIR/RemoteConnectionOverviewView.swift"
test -f "$REMOTE_DIR/RemoteVoicePipelineView.swift"
test -f "$REMOTE_DIR/RemoteButtonMappingView.swift"
test -f "$REMOTE_DIR/RemoteSupportView.swift"
test -f "$REMOTE_DIR/RemoteButtonGuideView.swift"
test -f "$REMOTE_DIR/RemoteControlIllustrationView.swift"
grep -Fq 'case remote' "$MAIN"
grep -Fq 'case .remote: return "遥控器"' "$MAIN"
grep -Fq 'case .remote:' "$PANEL"
grep -Fq 'buildRemoteInspectorPage()' "$PANEL"

for text in '设备' '语音链路' '按键映射' '权限与隐私' '使用与排障' '设备与按键说明' 'Home + Menu' '开始扫描' '不使用虚拟麦克风'; do
  rg -Fq "$text" "$REMOTE_DIR"
done

grep -Fq 'setAccessibilityLabel("启用遥控器输入")' "$REMOTE_DIR/RemoteConnectionOverviewView.swift"
grep -Fq 'setAccessibilityLabel("开始扫描小米遥控器")' "$REMOTE_DIR/RemoteConnectionOverviewView.swift"
grep -Fq 'setAccessibilityLabel' "$REMOTE_DIR/RemoteButtonGuideView.swift"
grep -Fq 'onRemoteEnabledChange' "$MAIN"
grep -Fq 'onRemotePrimaryAction' "$MAIN"
grep -Fq 'onRemoteMappingChange' "$MAIN"
grep -Fq 'updateRemoteInputSnapshot' "$REMOTE_MAIN"

if rg -n 'WKWebView|WebView|iframe|SayAll|MiRemoteV|BlackHole' "$REMOTE_MAIN" "$REMOTE_DIR"; then
  print -u2 "Remote tab must be native and must not expose excluded integration/assets"
  exit 1
fi

print "RemoteTabBoundaryCheck passed"
