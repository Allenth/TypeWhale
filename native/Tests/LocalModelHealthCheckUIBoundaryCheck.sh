#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+LocalModelHealthCheck.swift"
SERVICE="$ROOT/native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift"

require_text() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if ! grep -Fq "$needle" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

test -f "$ACTIONS"
require_text 'optionRow("本地模型检测"' "$LAYOUT" \
  'The model panel must contain an inline local-model check row.'
require_text '尚未检测' "$MAIN" \
  'The health check needs a neutral initial state.'
require_text '开始检测' "$MAIN" \
  'The health check needs an explicit start button.'
require_text 'configureLocalModelHealthCheckControls()' "$MAIN" \
  'The health-check controls must be configured before layout.'
require_text '检测本地整理模型' "$CONFIG" \
  'The start button needs an accessibility label.'
require_text '复制本地模型诊断' "$CONFIG" \
  'The copy button needs an accessibility label.'
require_text 'localModelHealthCheckTask == nil' "$ACTIONS" \
  'Repeated clicks must not start a second health check.'
require_text 'localModelHealthCheckButton.isEnabled = false' "$ACTIONS" \
  'The start button must be disabled while checking.'
require_text 'localModelHealthCheckButton.title = "再次检测"' "$ACTIONS" \
  'The completed state must allow an explicit rerun.'
require_text 'case "runtime_busy", "check_in_progress"' "$ACTIONS" \
  'Temporary busy states must be rendered separately from an unhealthy model.'
require_text '暂时无法检测' "$ACTIONS" \
  'Busy state copy must avoid declaring the model unavailable.'
require_text 'NSAccessibility.post' "$ACTIONS" \
  'Health-check status changes must notify assistive technology.'
require_text 'localModelHealthDiagnosticText = nil' "$ACTIONS" \
  'A new check must clear the previous diagnostic reference.'
require_text '诊断不含录音、转录、提示词和密钥' "$ACTIONS" \
  'The privacy boundary must be visible without relying on a tooltip.'
require_text 'NSPasteboard.general' "$ACTIONS" \
  'Diagnostics may be copied only from the explicit copy action.'
require_text '@objc func copyLocalModelHealthDiagnostic' "$ACTIONS" \
  'The diagnostic copy action is missing.'
require_text 'MainActor.run' "$ACTIONS" \
  'Async health-check results must update AppKit on the main actor.'
require_text 'localModelHealthCheckTask?.cancel()' "$MAIN" \
  'The UI task must be cancelled when the controller is released.'
require_text 'makeLocalModelHealthCheckService' "$SERVICE" \
  'The UI must use the production managed-runtime health-check factory.'

if rg -n 'DeepSeek|download|repair|重装|删除模型' "$ACTIONS"; then
  echo 'The local health-check action must not call cloud or repair flows.' >&2
  exit 1
fi

echo "LocalModelHealthCheckUIBoundaryCheck passed"
