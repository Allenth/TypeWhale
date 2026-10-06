#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOMAIN="$ROOT_DIR/native/Sources/Domain/ASRDomain.swift"
CANDIDATES="$ROOT_DIR/native/Sources/Domain/ASRBenchmarkDomain.swift"

for retired in zipformerSherpa qwen3Sherpa paraformerContextual paraformerZH seacoParaformer whisperSmallMLX; do
  ! grep -Eq "case .*\\b${retired}\\b" "$DOMAIN"
done

for retained in senseVoice parakeetSherpa funASRNano qwen3MLX06B qwen3MLX17B; do
  grep -Eq "case .*\\b${retained}\\b" "$DOMAIN"
done

grep -Fq '"zipformerSherpa"' "$DOMAIN"
grep -Fq '"qwen3ASR"' "$DOMAIN"
grep -Fq 'return .senseVoice' "$DOMAIN"
! grep -Fq 'zipformer-bilingual-zh-en-sherpa-int8' "$CANDIDATES"
! grep -Fq 'whisper-small-mlx' "$CANDIDATES"

RUNTIME_FILES=(
  "$ROOT_DIR/native/Sources/Infrastructure/ASR/ASRModelRegistry.swift"
  "$ROOT_DIR/native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift"
  "$ROOT_DIR/native/Resources/funasr_asr_worker.py"
  "$ROOT_DIR/native/Resources/mlx_asr_worker.py"
  "$ROOT_DIR/native/Helpers/TypeWhaleSherpaASR.swift"
  "$ROOT_DIR/native/Resources/local-candidate-admission.json"
  "$ROOT_DIR/native/Sources/Infrastructure/Models/ModelManifests.swift"
  "$ROOT_DIR/native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift"
  "$ROOT_DIR/native/Sources/Infrastructure/Models/ManagedASRModelDownloader.swift"
  "$ROOT_DIR/native/Sources/Presentation/Main/MainViewController+Actions.swift"
  "$ROOT_DIR/tools/asr-eval/run_local_candidate_matrix.py"
  "$ROOT_DIR/tools/asr-eval/run_funasr_eval.py"
)

for file in "${RUNTIME_FILES[@]}"; do
  for retired_id in \
    zipformer-bilingual-zh-en-sherpa-int8 \
    qwen3-asr-0.6b-sherpa-int8 \
    paraformer-hotword-contextual \
    paraformer-zh \
    seaco-paraformer \
    whisper-small-mlx; do
    if grep -Fq "$retired_id" "$file"; then
      echo "Retired provider remains in $(basename "$file"): $retired_id" >&2
      exit 1
    fi
  done
done

echo "RetiredASRCandidateBoundaryCheck passed"
