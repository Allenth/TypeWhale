#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT/tools/asr-eval/run_local_candidate_matrix.py"
grep -q 'admittedCandidateIDs' "$ROOT/native/Sources/Infrastructure/ASR/ASRModelRegistry.swift"
grep -q 'local-candidate-admission.json' "$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
echo "LocalASRCandidateAdmissionCheck passed"
