#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
PANEL="$ROOT/native/Sources/Presentation/Main/ManagedLLMModelPanel.swift"
MODEL="$ROOT/native/Sources/Core/SmartInput/SmartAIModel.swift"
MODEL_LIST="$ROOT/native/Sources/Presentation/Main/ManagedASRModelListView.swift"

test ! -e "$PANEL"
grep -Fq 'case typeWhaleQwen3_4BInstruct' "$MODEL"
grep -Fq 'case deepSeekV4Flash' "$MODEL"
test "$(rg -c '^    case .* = ' "$MODEL")" -eq 2
grep -Fq 'for item in SmartAIModel.allCases' "$CONFIG"
grep -Fq 'validateAndSelectQwen' "$ACTIONS"
grep -Fq 'runtimeLocator.probe()' "$ACTIONS"
grep -Fq 'runtimeProbe.isReady' "$ACTIONS"
grep -Fq 'registry.readiness(for: .qwen3_4BInstruct2507_4bit)' "$ACTIONS"
grep -Fq 'syncSmartAIModelMenus(to: previousModel)' "$ACTIONS"
grep -Fq 'onSmartAIModelChange?(model)' "$ACTIONS"
grep -Fq '截图翻译共用当前所选模型' "$CONFIG"

if rg -n 'GPT-OSS|gptOSS|ManagedLLMModelPanel|configureManagedLLMPanel|renderManagedLLMPanel' \
  "$MAIN" "$LAYOUT" "$CONFIG" "$ACTIONS"; then
  echo "Legacy GPT-OSS product UI must be removed." >&2
  exit 1
fi

if rg -n 'Ollama|ollama\\.com|openQwen2BDownloadLink|openQwen35BDownloadLink|qwen3\\.5:2b|qwen3\\.6:35b|本地 2B|本地 9B|本地 35B' \
  "$MODEL" "$MODEL_LIST" "$CONFIG" "$LAYOUT"; then
  echo "The two-model product UI must not advertise legacy Ollama models." >&2
  exit 1
fi

if rg -n 'LM Studio|\.lmstudio|Terminal' \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedLLMDownloadManager.swift" \
  "$ROOT/native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift" \
  "$ROOT/native/Resources/managed_mlx_llm_worker.py"; then
  echo "Managed LLM product sources must be TypeWhale-owned and terminal-free." >&2
  exit 1
fi

if rg -n 'HarmonyTokenIDs|extract_harmony_final|reasoning_effort=' \
  "$ROOT/native/Resources/managed_mlx_llm_worker.py"; then
  echo "Managed MLX worker must decode standard Qwen generated text." >&2
  exit 1
fi

echo "ManagedLLMModelPanelBoundaryCheck passed"
