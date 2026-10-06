#!/bin/zsh
set -euo pipefail

# Stage A 契约锁：统一实时转录迁移的源码边界不变量。
# 见 docs/superpowers/plans/2026-07-18-unify-realtime-transcription-implementation-plan.md
#   - UI 层不选择/构造/粘贴最终文本，也不修补 transcript。
#   - 最终交付只承认生产实时缓存（realtime-preview-delivery-cache），shadow runtime 仅作诊断。

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PRESENTATION="$ROOT/native/Sources/Presentation"
DELIVERY="$ROOT/native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift"

# 不变量 1：Presentation 层不构造最终识别结果、不驱动粘贴、不做最终交付选择。
for forbidden in 'FinalRecognitionResult' 'PasteCoordinator' 'selectForFinalDelivery'; do
  if grep -rq "$forbidden" "$PRESENTATION"; then
    echo "BOUNDARY VIOLATION: Presentation 层不得引用 $forbidden（最终文本归 Application 层）"
    exit 1
  fi
done

# 不变量 2：胶囊视图不得对 transcript 做字符串裁剪/拼接（截断仅可用段落样式，不改文本）。
for view_dir in "$PRESENTATION/Capsule" "$PRESENTATION/ShadowPreview"; do
  for mutator in 'replacingOccurrences' 'removeSubrange' 'dropLast'; do
    if grep -rq "$mutator" "$view_dir"; then
      echo "BOUNDARY VIOLATION: $view_dir 不得用 $mutator 修补 transcript（UI 只展示，不裁剪最终文本）"
      exit 1
    fi
  done
done

# 不变量 3：最终交付选择存在，且不能返回 shadow runtime。
grep -Fq 'func selectForFinalDelivery' "$DELIVERY"
python3 - "$DELIVERY" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("func selectForFinalDelivery")
end = source.index("\n    }\n}", start)
body = source[start:end]
if "return shadowRuntimeSnapshot" in body:
    raise SystemExit("最终交付不能返回 shadowRuntimeSnapshot；shadow 只做诊断")
if "return realtimePreviewDeliverySnapshot" not in body:
    raise SystemExit("最终交付必须返回 realtimePreviewDeliverySnapshot")
PY

echo "UnifiedRealtimeSourceBoundaryCheck passed"
