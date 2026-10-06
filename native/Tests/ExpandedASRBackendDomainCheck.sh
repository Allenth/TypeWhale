#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOMAIN="$ROOT_DIR/native/Sources/Domain/ASRDomain.swift"

for backend in senseVoice parakeetSherpa funASRNano qwen3MLX06B qwen3MLX17B; do
  grep -Fq "case $backend" "$DOMAIN"
done

for retired in zipformerSherpa qwen3Sherpa paraformerContextual paraformerZH seacoParaformer whisperSmallMLX; do
  if grep -Eq "case .*\\b${retired}\\b" "$DOMAIN"; then
    echo "Retired backend remains selectable: $retired" >&2
    exit 1
  fi
  grep -Fq "\"$retired\"" "$DOMAIN"
done

grep -Fq 'case .qwen3MLX06B: return .qwen3MLX06B' "$DOMAIN"
grep -Fq 'case .qwen3MLX17B: return .qwen3MLX17B' "$DOMAIN"
grep -Fq '"qwen3ASR"' "$DOMAIN"
grep -Fq 'UserDefaults.standard.set(ASRBackend.senseVoice.rawValue' "$DOMAIN"

echo "ExpandedASRBackendDomainCheck passed"
