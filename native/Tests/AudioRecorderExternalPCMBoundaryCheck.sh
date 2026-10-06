#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RECORDER="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

grep -Fq 'func startExternal(' "$RECORDER"
grep -Fq 'func appendExternalPCM16(' "$RECORDER"
grep -Fq 'private func processCanonicalBuffer(' "$RECORDER"
grep -Fq 'processCanonicalBuffer(canonical, taskID: taskID)' "$RECORDER"

python3 - "$RECORDER" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("func startExternal(")
append = source.index("func appendExternalPCM16(", start)
external = source[start:append]
if "startInputRouteMonitoring()" in external or "installCaptureTap" in external:
    raise SystemExit("external PCM input must not activate microphone capture or route monitoring")

captured = source.index("private func processCapturedBuffer(")
canonical = source.index("private func processCanonicalBuffer(")
section = source[captured:canonical]
if "processCanonicalBuffer(canonical, taskID: taskID)" not in section:
    raise SystemExit("microphone and remote input must converge on processCanonicalBuffer")
PY

print "AudioRecorderExternalPCMBoundaryCheck passed"
