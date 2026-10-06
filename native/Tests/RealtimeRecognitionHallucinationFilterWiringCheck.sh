#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIPELINE="$ROOT/native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift"
PROVIDER="$ROOT/native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift"
UI_DIR="$ROOT/native/Sources/Presentation"

grep -Fq 'RealtimeRecognitionHallucinationFilter' "$PIPELINE"
grep -Fq 'realtime_result_suppressed' "$PIPELINE"
grep -Fq 'RealtimeRecognitionHallucinationFilter' "$PROVIDER"
grep -Fq 'realtime_result_suppressed' "$PROVIDER"

python3 - "$PIPELINE" "$PROVIDER" <<'PY'
from pathlib import Path
import sys

for path in map(Path, sys.argv[1:]):
    source = path.read_text()
    decision = source.find("hallucinationFilter.evaluate")
    mutation_markers = [
        source.find("reducer.apply", decision),
        source.find("reconciler.consume", decision),
    ]
    mutation = min(marker for marker in mutation_markers if marker >= 0)
    if decision < 0 or decision > mutation:
        raise SystemExit(f"{path.name}: filter must run before reducer/reconciler mutation")
PY

if rg -q 'RealtimeRecognitionHallucinationFilter|realtime_result_suppressed' "$UI_DIR"; then
  echo "Hallucination filtering must not be implemented in Presentation/UI" >&2
  exit 1
fi

echo "RealtimeRecognitionHallucinationFilterWiringCheck passed"
