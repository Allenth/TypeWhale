#!/usr/bin/env bash
set -euo pipefail

COORDINATOR="native/Sources/Application/SpeechInputCoordinator.swift"

/usr/bin/python3 - <<'PY'
from pathlib import Path

source = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()

def function_body(signature: str, next_signature: str) -> str:
    start = source.index(signature)
    end = source.index(next_signature, start + len(signature))
    return source[start:end]

recording_start = source[source.index('popup.show(state: "录音中", draft: "")'):]
production_begin = recording_start.index("beginProductionPreview(taskID: taskID, deliversText: capsulePreviewEnabled)")
shadow_begin = recording_start.index("beginShadowPreview(taskID: taskID)")
if production_begin > shadow_begin:
    raise SystemExit("production preview must begin before optional shadow preview")

shadow_end = function_body(
    "private func endShadowPreview(cancelled: Bool)",
    "private func clearActiveRecording("
)
for forbidden in (
    "productionPreviewStateBridge",
    "productionPreviewTextCoordinator",
    "productionRealtimePreviewDeliveryCache",
):
    if forbidden in shadow_end:
        raise SystemExit(f"shadow teardown must not touch {forbidden}")

production_begin_body = function_body(
    "private func beginProductionPreview(taskID: UUID, deliversText: Bool)",
    "private func beginShadowPreview(taskID: UUID)"
)
for required in (
    "productionRealtimePreviewDeliveryCache.reset(",
    "productionPreviewStateBridge.begin(sessionID: sessionID)",
    "deliversText: deliversText",
):
    if required not in production_begin_body:
        raise SystemExit(f"production begin is missing {required}")

clear_body = source[source.index("private func clearActiveRecording("):source.index("private func cancelAutoFinishTimer", source.index("private func clearActiveRecording("))]
if "endProductionPreview(cancelled: true)" not in clear_body:
    raise SystemExit("whole-session cancellation must end production preview explicitly")

prepare_body = function_body(
    "private func prepareShadowPreviewForFinalDelivery(recordingDuration: TimeInterval? = nil)",
    "private func finishShadowPreviewForFinalDelivery("
)
if "prepareProductionPreviewForFinalDelivery(recordingDuration: recordingDuration)" not in prepare_body:
    raise SystemExit("normal stop must complete production preview explicitly")
PY

echo "ProductionPreviewLifecycleIsolationBoundaryCheck passed"
