#!/usr/bin/env bash
set -euo pipefail

SOURCE="native/Sources/Application/SpeechInputCoordinator.swift"

python3 - <<'PY'
from pathlib import Path

source = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()

def body(name: str, next_marker: str) -> str:
    start = source.index(name)
    end = source.index(next_marker, start)
    return source[start:end]

prepare = body(
    "    private func prepareShadowPreviewForFinalDelivery(",
    "\n    private func finishShadowPreviewForFinalDelivery"
)
finish = body(
    "    private func finishShadowPreviewForFinalDelivery(",
    "\n    private func drainShadowAudioFrameDeliveryForFinalDelivery"
)
complete = body(
    "    private func startFinalRecognition(",
    "\n    private func beginShadowPreview"
)
drain = body(
    "    private func drainShadowAudioFrameDeliveryForFinalDelivery(",
    "\n    private func endShadowPreview"
)
admission = body(
    "    private func canAdmitSenseVoiceShadowRecognition()",
    "\n    private func beginShadowAudioFrameDelivery"
)

if "shadowAudioFrameTask?.cancel()" in prepare:
    raise SystemExit("prepareShadowPreviewForFinalDelivery must not cancel audio delivery before final handoff")
if "unsubscribeFromAudioFrames" in prepare:
    raise SystemExit("prepareShadowPreviewForFinalDelivery must not unsubscribe audio delivery before final handoff")
if "await drainShadowAudioFrameDeliveryForFinalDelivery()" not in finish:
    raise SystemExit("finishShadowPreviewForFinalDelivery must drain audio delivery before completing runtime")
if "let shadowRuntimeSnapshot = await runtime?.completeForDelivery()" not in finish:
    raise SystemExit("finishShadowPreviewForFinalDelivery must complete the real shadow runtime")
if "await candidateRuntime?.complete()" not in finish:
    raise SystemExit("finishShadowPreviewForFinalDelivery must still close the candidate diagnostic runtime")
if "let realtimePreviewDeliverySnapshot = productionRealtimePreviewDeliveryCache.deliverySnapshot()" not in finish:
    raise SystemExit("finishShadowPreviewForFinalDelivery must read final delivery cache from production cache")
if "let realtimePreviewDeliverySnapshot = await candidateRuntime?.completeForDelivery()" in finish:
    raise SystemExit("finishShadowPreviewForFinalDelivery must not read final delivery cache from candidate runtime")
if "realtimePreviewDeliverySnapshot: candidateSnapshots.realtimePreviewDelivery" not in complete:
    raise SystemExit("completeRecognition must pass the realtime preview delivery cache into FinalDeliveryUseCase")
if "shadowRuntimeSnapshot: candidateSnapshots.shadow" not in complete:
    raise SystemExit("completeRecognition must pass shadow runtime only as diagnostic input into FinalDeliveryUseCase")
if finish.index("let shadowRuntimeSnapshot = await runtime?.completeForDelivery()") > finish.index("await candidateRuntime?.complete()"):
    raise SystemExit("real shadow runtime must be completed before candidate diagnostic runtime close")
if "task.cancel()" not in drain or "unsubscribeFromAudioFrames" not in drain:
    raise SystemExit("drainShadowAudioFrameDeliveryForFinalDelivery must retain a bounded timeout cleanup")
if "if !recorder.isRecording" not in admission or "return true" not in admission:
    raise SystemExit("stop-time SenseVoice final tail must be admitted after recorder.stop()")

print("CandidateFinalDeliveryBoundaryCheck passed")
PY
