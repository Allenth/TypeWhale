#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECTION="$ROOT/native/Sources/Presentation/Capsule/MainCapsuleLegacyStatusProjection.swift"
VIEW="$ROOT/native/Sources/Presentation/Capsule/RecordingCapsuleView.swift"

if ! grep -q 'case "整理中"' "$PROJECTION"; then
  echo "Legacy status projection must map 整理中 explicitly." >&2
  exit 1
fi

if ! grep -q 'case "无输入已停止"' "$PROJECTION"; then
  echo "Legacy status projection must map 无输入已停止 explicitly." >&2
  exit 1
fi

if ! grep -q 'case "录音失败", "保存失败", "识别失败"' "$PROJECTION"; then
  echo "Legacy status projection must map legacy failure statuses explicitly." >&2
  exit 1
fi

if ! grep -q "renderState.statusText.draw" "$VIEW"; then
  echo "RecordingCapsuleView must keep drawing status text from MainCapsuleRenderState." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Provider|Reconciler|ShadowPreview|CandidatePreview|SmartRewriteEngine|SenseVoice|VAD'
if grep -E "$FORBIDDEN_PATTERN" "$PROJECTION" "$VIEW" >/dev/null; then
  echo "Status display migration must not touch delivery/provider/shadow/candidate/rewrite/asr paths." >&2
  exit 1
fi

echo "MainCapsuleStatusMigrationBoundaryCheck passed"
