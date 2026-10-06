#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift"

test -f "$BACKEND"
grep -q 'final class SherpaNativeTTSBackend: OpenClawTTSBackend' "$BACKEND"
grep -q 'Process()' "$BACKEND"
grep -q 'sherpa-onnx-offline-tts' "$ROOT/native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift"
grep -q 'TYPEWHALE_SHERPA_NATIVE_TTS' "$ROOT/native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift"
grep -q 'vits-model' "$BACKEND"
grep -q 'vits-lexicon' "$BACKEND"
grep -q 'vits-tokens' "$BACKEND"
grep -q 'vits-dict-dir' "$BACKEND"
grep -q 'output-filename' "$BACKEND"
! grep -q 'python' "$BACKEND"
! grep -q 'MeloTTSRunner' "$BACKEND"
! grep -q 'melo.api' "$BACKEND"
grep -q 'let workerScriptURL: URL?' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
! awk '/func speak\(/,/private func makeRequest/' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift" | grep -q 'guard let workerURL'

echo "SherpaNativeTTSBackendSourceCheck passed"
