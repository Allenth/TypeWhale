#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController.swift"
LAYOUT="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
CONFIG="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
ACTIONS="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+Actions.swift"

grep -Fq 'case models' "$MAIN"
grep -Fq 'case .models: return "模型"' "$MAIN"
if grep -Fq 'case status' "$MAIN"; then
  echo "Status must move into 常用; it must not remain a standalone inspector tab" >&2
  exit 1
fi

common_block="$(awk '/case \.common:/{flag=1} /case \.intelligence:/{if(flag){exit}} flag{print}' "$LAYOUT")"
models_block="$(awk '/case \.models:/{flag=1} /case \.openClaw:/{if(flag){exit}} flag{print}' "$LAYOUT")"

grep -Fq 'inspectorGroup("状态", buildStatusPanelContent())' <<<"$common_block"
grep -Fq 'inspectorGroup("ASR 模型", buildManagedModelContent())' <<<"$models_block"
grep -Fq 'inspectorGroup("整理模型", buildModelTabSmartAIModelContent())' <<<"$models_block"
if grep -Fq 'buildManagedLLMModelContent' <<<"$models_block"; then
  echo "The legacy standalone managed-model panel must not remain in the model tab" >&2
  exit 1
fi
grep -Fq '本地直驱 Qwen3 4B' "$LAYOUT"
grep -Fq 'let modelTabSmartAIModelMode = NSPopUpButton()' "$MAIN"
grep -Fq 'configureSmartAIModelMenu(model, popup: modelTabSmartAIModelMode)' "$CONFIG"
grep -Fq 'modelTabSmartAIModelMode.target = self; modelTabSmartAIModelMode.action = #selector(selectSmartAIModel)' "$MAIN"
grep -Fq 'syncSmartAIModelMenus(to: nextSmartAIModel)' "$ACTIONS"
grep -Fq 'smartAIModelMode.widthAnchor.constraint(equalToConstant: 240)' "$LAYOUT"
grep -Fq 'modelTabSmartAIModelMode.widthAnchor.constraint(equalToConstant: 240)' "$LAYOUT"

echo "InspectorModelTabLayoutCheck passed"
