#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOMAIN="$ROOT_DIR/native/Sources/Domain/ASRDomain.swift"

grep -Fq 'case senseVoice' "$DOMAIN"
grep -Fq 'case funASRNano' "$DOMAIN"
grep -Fq 'return "Fun-ASR Nano"' "$DOMAIN"
grep -Fq '?? .senseVoice' "$DOMAIN"

if grep -Fq 'case automatic' "$DOMAIN"; then
  echo "Legacy automatic backend must not remain user-selectable" >&2
  exit 1
fi
if grep -Fq 'case qwen3ASR {' "$DOMAIN"; then
  echo "Legacy monolithic Qwen3-ASR backend must not return" >&2
  exit 1
fi

grep -Fq 'case qwen3MLX06B' "$DOMAIN"
grep -Fq 'case qwen3MLX17B' "$DOMAIN"
grep -Fq 'supportsFunASRSidecarWarmup' "$DOMAIN"
grep -Fq 'case .funASRNano: return true' "$DOMAIN"

echo "FunASRBackendDomainCheck passed"
