#!/usr/bin/env bash
set -euo pipefail

layout="native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
actions="native/Sources/Presentation/Main/MainViewController+Actions.swift"

rg -q '粘贴与发送' "$layout"
rg -q '粘贴后自动发送' "$layout"
rg -q 'initialSection: \.rewrite|ApplicationScopeSection\.rewrite' "$actions"
rg -q 'initialSection: \.autoSend|ApplicationScopeSection\.autoSend' "$actions"
rg -q 'AutoSendSettingsStore\.save' "$actions"
rg -q 'SmartRewriteAutoRuleStore\.save' "$actions"

echo "ApplicationScopeSettingsEntryCheck passed"
