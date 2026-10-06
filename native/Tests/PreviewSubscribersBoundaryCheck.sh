#!/usr/bin/env bash
set -euo pipefail

APP="native/Sources/Application"
PRESENTATION="native/Sources/Presentation"
PRODUCTION_COORDINATOR="$APP/RealtimeTranscription/ProductionPreviewTextCoordinator.swift"
PRODUCTION_BRIDGE="$APP/RealtimeTranscription/ProductionPreviewStateBridge.swift"
PROJECTOR="$APP/RealtimeTranscription/PreviewDisplaySnapshotProjector.swift"
SPEECH_COORDINATOR="$APP/SpeechInputCoordinator.swift"
SHADOW_COORDINATOR="$PRESENTATION/ShadowPreview/ShadowPreviewCoordinator.swift"

for file in \
    "$PRODUCTION_COORDINATOR" \
    "$PRODUCTION_BRIDGE" \
    "$PROJECTOR" \
    "$SPEECH_COORDINATOR" \
    "$SHADOW_COORDINATOR"; do
    test -f "$file"
done

grep -Fq 'private let productionPreviewStateBridge = ProductionPreviewStateBridge()' "$SPEECH_COORDINATOR"
grep -Fq 'private lazy var productionPreviewTextCoordinator = ProductionPreviewTextCoordinator(sink: popup)' "$SPEECH_COORDINATOR"
grep -Fq 'private var projection = PreviewDisplaySnapshotProjector()' "$PRODUCTION_COORDINATOR"
grep -Fq 'struct PreviewDisplaySnapshotProjector' "$PROJECTOR"

if rg -n 'ShadowPreviewRuntimeGate|ShadowPreviewCoordinator|CandidatePreviewCoordinator|CandidatePreviewView|ShadowPreviewView' "$PRODUCTION_COORDINATOR" "$PRODUCTION_BRIDGE" "$PROJECTOR"; then
    echo "Production preview data path must not reference diagnostic preview types" >&2
    exit 1
fi

if rg -n 'FinalDeliveryUseCase|FinalRecognitionUseCase|PasteCoordinator|CandidateDeliverySnapshot' \
    "$PRESENTATION/Capsule" \
    "$PRESENTATION/MinimalBlackPreview" \
    "$PRESENTATION/ShadowPreview"; then
    echo "Preview views/coordinators must not reference final delivery types" >&2
    exit 1
fi

if rg -n 'FinalDeliveryUseCase|FinalRecognitionUseCase|PasteCoordinator|CandidateDeliverySnapshot' "$PRODUCTION_COORDINATOR" "$PRODUCTION_BRIDGE" "$PROJECTOR"; then
    echo "Production preview data path must not decide final delivery" >&2
    exit 1
fi

python3 - <<'PY'
from pathlib import Path

source = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()
recording_start = source.index("beginProductionPreview(taskID: taskID, deliversText: capsulePreviewEnabled)")
shadow_start = source.index("beginShadowPreview(taskID: taskID)", recording_start)
if recording_start > shadow_start:
    raise SystemExit("product preview subscription must start before diagnostic preview")

production_begin = source[source.index("private func beginProductionPreview"):source.index("private func beginShadowPreview")]
if "productionPreviewTextCoordinator.begin(" not in production_begin or "deliversText: deliversText" not in production_begin:
    raise SystemExit("product preview coordinator must subscribe to production states")

shadow_begin = source[source.index("private func beginShadowPreview"):source.index("private func makeLocalSenseVoiceShadowRuntime")]
if "shadowPreviewCoordinator.begin(" not in shadow_begin:
    raise SystemExit("shadow coordinator must remain the explicit diagnostic subscriber")
for forbidden in ("candidatePreviewCoordinator", "productionPreviewStateBridge", "productionPreviewTextCoordinator"):
    if forbidden in shadow_begin:
        raise SystemExit(f"shadow start must not own {forbidden}")
PY

echo "PreviewSubscribersBoundaryCheck passed"
