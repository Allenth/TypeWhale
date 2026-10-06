#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
ONLINE_SOURCES=(
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/MiMoHTTPTransport.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift"
  "$ROOT/native/Sources/Application/RealtimeTranscription/OnlineASRProviderFactory.swift"
)

if rg -n 'finishRecording\(|PasteCoordinator|committedPreviewText\s*=|latestPreviewText\s*=|startFinalRecognition\(|onVoiceProbe\s*=' "${ONLINE_SOURCES[@]}"; then
    echo "online-owned source crossed a protected production boundary" >&2
    exit 1
fi

python3 - "$COORDINATOR" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("    private func beginShadowPreview(taskID: UUID) {")
end = source.index("\n    private func publishShadowPreview", start)
block = source[start:end]
helper_start = source.index("    private func makeLocalSenseVoiceShadowRuntime(")
helper = source[helper_start:end]

required = [
    'ShadowPreviewRuntimeGate.shouldStart(isEnabled: controller.shadowPreviewEnabled)',
    '--debug-shadow-sensevoice',
    '--debug-shadow-fake-stream',
    'OnlineASRSettingsStore().load()',
    'OnlineASRProviderFactory(',
    'makeLocalSenseVoiceShadowRuntime(',
]
for needle in required:
    if needle not in block:
        raise SystemExit(f"missing session-start boundary: {needle}")

order = [
    block.index('--debug-shadow-sensevoice'),
    block.index('--debug-shadow-fake-stream'),
    block.index('OnlineASRSettingsStore().load()'),
    block.index('case .ready(let provider):'),
    block.index('source: "missing_credential_fallback"'),
    block.index('source: "local_fallback"'),
    helper_start - start,
]
if order != sorted(order):
    raise SystemExit("provider precedence is not debug SenseVoice → debug fake → online ready → local SenseVoice → Legacy safety fallback")

if source.count('OnlineASRSettingsStore().load()') != 1:
    raise SystemExit("online selection must be loaded exactly once per session-start source path")
if source.count('OnlineASRProviderFactory(') != 1:
    raise SystemExit("online factory creation must exist only at beginShadowPreview")
if 'subscribeToAudioFrames(capacity: 8)' not in source:
    raise SystemExit("online provider must reuse the existing capacity-8 audio fan-out")
for required_helper in ('SenseVoiceSnapshotProvider(', 'provider=legacy_adapter reason=missing_local_configuration'):
    if required_helper not in helper:
        raise SystemExit(f"missing local fallback boundary: {required_helper}")
for forbidden in ('finishRecording(', 'PasteCoordinator', 'committedPreviewText =', 'latestPreviewText =', 'startFinalRecognition(', 'onVoiceProbe ='):
    if forbidden in block or forbidden in helper:
        raise SystemExit(f"online shadow block crossed protected boundary: {forbidden}")
PY

echo "OnlineASRShadowIsolationCheck passed"
