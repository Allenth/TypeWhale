#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

python3 - "$COORDINATOR" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
begin_start = source.index("    private func beginShadowPreview(taskID: UUID) {")
begin_end = source.index("\n    private func publishShadowPreview", begin_start)
begin = source[begin_start:begin_end]

helper_signature = "    private func makeLocalSenseVoiceShadowRuntime("
if helper_signature not in source:
    raise SystemExit("normal local shadow route is missing the SenseVoice assembly helper")

helper_start = source.index(helper_signature)
helper_end = source.index("\n    private func publishShadowPreview", helper_start)
helper = source[helper_start:helper_end]

for label in ('source: "local_fallback"', 'source: "missing_credential_fallback"'):
    if label not in begin:
        raise SystemExit(f"normal local route is missing {label}")

disabled_start = begin.index("            case .disabled:")
disabled = begin[disabled_start:]
missing_start = begin.index("            case .unavailable(.missingCredential):")
missing = begin[missing_start:disabled_start]

legacy_direct = "runtime = ShadowTranscriptionRuntime(sessionID: sessionID)"
if legacy_direct in missing or legacy_direct in disabled:
    raise SystemExit("online-off or missing-key route still instantiates Legacy directly")

required_helper_fragments = (
    "guard let configuration = activeSession?.configuration else",
    "SenseVoiceSnapshotProvider(",
    "SenseVoiceSnapshotNativeRecognizer(",
    "ClosureSenseVoiceShadowResourceAdmission",
    "canAdmitSenseVoiceShadowRecognition()",
    "senseVoiceShadowProvider = provider",
    "ShadowTranscriptionRuntime(sessionID: sessionID, provider: provider)",
    "provider=legacy_adapter reason=missing_local_configuration",
    "provider=sensevoice_snapshot source=\\(source)",
)
for fragment in required_helper_fragments:
    if fragment not in helper:
        raise SystemExit(f"local SenseVoice assembly helper is missing: {fragment}")

for forbidden in (
    "finishRecording(",
    "PasteCoordinator",
    "committedPreviewText =",
    "latestPreviewText =",
    "startFinalRecognition(",
):
    if forbidden in helper:
        raise SystemExit(f"local shadow assembly crossed production boundary: {forbidden}")
PY

echo "LocalSenseVoiceShadowRoutingCheck passed"
