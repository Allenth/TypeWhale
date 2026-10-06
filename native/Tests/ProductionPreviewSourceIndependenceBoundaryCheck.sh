#!/usr/bin/env bash
set -euo pipefail

COORDINATOR="native/Sources/Application/SpeechInputCoordinator.swift"
BRIDGE="native/Sources/Application/RealtimeTranscription/ProductionPreviewStateBridge.swift"

test -f "$BRIDGE"

grep -Fq 'private let productionPreviewStateBridge = ProductionPreviewStateBridge()' "$COORDINATOR"
grep -Fq 'beginProductionPreview(taskID: taskID, deliversText: capsulePreviewEnabled)' "$COORDINATOR"
grep -Fq 'productionPreviewStateBridge.begin(sessionID: sessionID)' "$COORDINATOR"
grep -Fq 'productionPreviewStateBridge.consume(productSnapshot)' "$COORDINATOR"

/usr/bin/python3 - <<'PY'
from pathlib import Path

source = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()
begin = source.index("private func beginProductionPreview")
end = source.index("private func beginShadowPreview")
body = source[begin:end]

bridge_begin = body.index("productionPreviewStateBridge.begin(sessionID: sessionID)")
if body.count("productionPreviewTextCoordinator.begin") != 1:
    raise SystemExit("production preview coordinator must have exactly one independent begin call")

shadow_begin = source[source.index("private func beginShadowPreview"):source.index("private func makeLocalSenseVoiceShadowRuntime")]
for forbidden in ("productionPreviewStateBridge", "productionPreviewTextCoordinator", "productionRealtimePreviewDeliveryCache"):
    if forbidden in shadow_begin:
        raise SystemExit(f"shadow preview start must not own {forbidden}")

apply_realtime = source[source.index("private func applyRealtimePreview"):source.index("private func scheduleRealtimeSnapshotTimeout")]
if apply_realtime.index("productionPreviewStateBridge.consume(productSnapshot)") > apply_realtime.index("publishShadowPreview("):
    raise SystemExit("production bridge must consume realtime product snapshot before diagnostic publish")

experimental = source[source.index("private func applyExperimentalPreviewState"):source.index("private func completeLongFormIncrementalFinalization")]
if experimental.index("productionPreviewStateBridge.consume(productSnapshot)") > experimental.index("publishShadowPreview("):
    raise SystemExit("production bridge must consume experimental product snapshot before diagnostic publish")
PY

if rg -n 'ShadowPreviewCoordinator|CandidatePreviewCoordinator|ShadowPreviewRuntimeGate|FinalDeliveryUseCase|FinalRecognitionUseCase|PasteCoordinator' "$BRIDGE"; then
    echo "ProductionPreviewStateBridge must not reference diagnostic UI or final delivery types" >&2
    exit 1
fi

echo "ProductionPreviewSourceIndependenceBoundaryCheck passed"
