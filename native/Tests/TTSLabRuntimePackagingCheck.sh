#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
grep -q 'tts_benchmark_worker.py' "$ROOT/native/build_native_app.sh"
! grep -q 'typewhale-ttskit-worker' "$ROOT/native/build_native_app.sh"
! grep -q 'TTSKitBridge' "$ROOT/native/build_native_app.sh"
! grep -q 'tts_engines' "$ROOT/native/build_native_app.sh"
ditto_line="$(grep -n 'ditto "$ROOT/native/Resources" "$CONTENTS/Resources"' "$ROOT/native/build_native_app.sh" | cut -d: -f1)"
prune_line="$(grep -n 'find "$CONTENTS/Resources" -name __pycache__' "$ROOT/native/build_native_app.sh" | tail -1 | cut -d: -f1)"
[[ "$prune_line" -gt "$ditto_line" ]]
echo "TTSLabRuntimePackagingCheck passed"
