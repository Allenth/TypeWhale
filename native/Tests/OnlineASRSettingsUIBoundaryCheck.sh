#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main"

rg -q 'let onlineASRProviderMode = NSPopUpButton\(\)' "$MAIN/MainViewController.swift"
rg -q 'let doubaoASRKeyButton = NSButton' "$MAIN/MainViewController.swift"
rg -q 'let mimoASRKeyButton = NSButton' "$MAIN/MainViewController.swift"
rg -q '在线旁路：关闭 / 豆包 ASR / MiMo‑V2\.5-ASR' "$MAIN"
rg -q '在线音频仅在选择对应服务并开始下一轮录音后发送；不参与最终识别和粘贴。' "$MAIN"
rg -q 'NSSecureTextField' "$MAIN/MainViewController+Actions.swift"
rg -q 'title: "保存"' "$MAIN/MainViewController+Actions.swift"
rg -q 'title: "清除"' "$MAIN/MainViewController+Actions.swift"
rg -q 'title: "取消"' "$MAIN/MainViewController+Actions.swift"
rg -q 'OnlineASRCredentialStore\(\)\.save' "$MAIN/MainViewController+Actions.swift"
rg -q 'OnlineASRCredentialStore\(\)\.delete' "$MAIN/MainViewController+Actions.swift"
rg -q '\.has\(\.doubaoAPIKey\)' "$MAIN"
rg -q '\.has\(\.mimoAPIKey\)' "$MAIN"
rg -q 'setAccessibilityLabel\("在线旁路服务"\)' "$MAIN"
rg -q 'setAccessibilityLabel\("豆包 API Key"\)' "$MAIN"
rg -q 'setAccessibilityLabel\("MiMo API Key"\)' "$MAIN"
rg -q 'OnlineASRSettingsStore\(\)\.save' "$MAIN/MainViewController+Actions.swift"
rg -q 'name: \.shadowPreviewSettingDidChange' "$MAIN/MainViewController+Actions.swift"
rg -q '未配置 Key；不会发送在线音频，下一轮继续使用本地旁路。' "$MAIN/MainViewController+Actions.swift"
rg -q 'case \.doubao:.*has\(\.doubaoAPIKey\)' "$MAIN/MainViewController+Actions.swift"
rg -q 'case \.mimoV25:.*has\(\.mimoAPIKey\)' "$MAIN/MainViewController+Actions.swift"

if rg -n 'OnlineASRCredentialStore\(\)\.load|credentialStore\.load' "$MAIN"; then
    echo "UI source must never load credential values for display" >&2
    exit 1
fi

echo "OnlineASRSettingsUIBoundaryCheck passed"
