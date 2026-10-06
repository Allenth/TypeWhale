#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
ADAPTERS="$ROOT/native/Sources/Application/LocalASREngineAdapters.swift"
BUILD="$ROOT/native/build_native_app.sh"
CAPABILITIES="$ROOT/native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift"

grep -Fq 'SherpaLocalEngineAdapter' "$ADAPTERS"
grep -Fq 'TypeWhaleSherpaASR' "$COORDINATOR"
grep -Fq 'TypeWhaleSherpaASR.swift' "$BUILD"
grep -Fq 'TypeWhaleSherpaASR' "$BUILD"
grep -Fq 'supportsHotwords: false' "$CAPABILITIES"
if grep -Fq '.sherpa: SherpaBenchmarkAdapter()' "$COORDINATOR"; then
  echo "production must not run optional Sherpa candidates in the App process" >&2
  exit 1
fi
echo "SherpaCandidateIsolationBoundaryCheck passed"
