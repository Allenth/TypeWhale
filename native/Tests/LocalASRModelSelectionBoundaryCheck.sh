#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOMAIN="$ROOT_DIR/native/Sources/Domain/ASRDomain.swift"
REGISTRY="$ROOT_DIR/native/Sources/Infrastructure/ASR/ASRModelRegistry.swift"
CONFIG="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
ACTIONS="$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+Actions.swift"

grep -Fq 'case qwen3MLX06B' "$DOMAIN"
grep -Fq 'case qwen3MLX06B' "$DOMAIN"
grep -Fq 'case qwen3MLX17B' "$DOMAIN"
grep -Fq 'models--mlx-community--Qwen3-ASR-0.6B-8bit' "$REGISTRY"
grep -Fq 'liveASRModelRegistry.descriptor(for: item.candidateID)' "$CONFIG"
grep -Fq 'ASRBackend.fromMenuTag' "$ACTIONS"
grep -Fq 'liveASRModelRegistry.descriptor(for: selectedBackend.candidateID)' "$ACTIONS"
if grep -Fq '尚未接入最终识别执行器' "$ACTIONS"; then
  echo "ready MLX models must not be described as disconnected" >&2
  exit 1
fi

echo "LocalASRModelSelectionBoundaryCheck passed"
