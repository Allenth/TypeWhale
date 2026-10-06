#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"

if grep -q "候选胶囊" "$LAYOUT" "$CONFIG"; then
  echo "Candidate capsule must not appear as a product settings entry." >&2
  exit 1
fi

if ! grep -q 'subSectionView("诊断工具（实验）"' "$LAYOUT"; then
  echo "Shadow/online sidepath controls must live under an explicit diagnostics subsection." >&2
  exit 1
fi

if ! grep -q 'optionRow("旁路预览（诊断）", shadowPreviewExperiment)' "$LAYOUT"; then
  echo "Shadow preview row must be labeled as diagnostics, not a normal product feature." >&2
  exit 1
fi

if ! grep -q 'optionRow("在线旁路（诊断）", onlineASRProviderMode)' "$LAYOUT"; then
  echo "Online sidepath row must be labeled as diagnostics." >&2
  exit 1
fi

if ! grep -q 'shadowPreviewExperiment.setAccessibilityLabel("旁路预览（诊断）")' "$CONFIG"; then
  echo "Accessibility label must match diagnostic positioning." >&2
  exit 1
fi

FORBIDDEN_PATTERN='FinalDeliveryUseCase|FinalRecognitionUseCase|LegacyRealtimePreviewDeliveryCache|RealtimePreviewDeliveryCache|CandidateDeliverySnapshot|PasteCoordinator|TranscriptionProvider|Reconciler|ShadowPreviewCoordinator|CandidatePreviewCoordinator'
if grep -E "$FORBIDDEN_PATTERN" "$LAYOUT" "$CONFIG" >/dev/null; then
  echo "Settings retirement must not touch runtime, delivery, provider, ASR, or cache paths." >&2
  exit 1
fi

echo "MainCapsuleRetirementSettingsBoundaryCheck passed"
