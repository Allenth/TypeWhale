#!/usr/bin/env bash
set -euo pipefail

/usr/bin/python3 - <<'PY'
from pathlib import Path

state = Path("native/Sources/Application/SpeechInputState.swift").read_text()
domain = Path("native/Sources/Domain/ASRDomain.swift").read_text()
coordinator = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()

assert "let reRecognizeWholeRecordingAfterStop: Bool" in state, \
    "SpeechSession must freeze the Final ASR policy"
assert "let reRecognizeWholeRecordingAfterStop: Bool" in domain, \
    "RecordingTask must carry the frozen Final ASR policy"
assert "reRecognizeWholeRecordingAfterStop: controller.reRecognizeWholeRecordingAfterStopEnabled" in coordinator, \
    "SpeechSession creation must capture the setting"
assert "reRecognizeWholeRecordingAfterStop: session.reRecognizeWholeRecordingAfterStop" in coordinator, \
    "RecordingTask must inherit the session policy"

start = coordinator.index("    private func startFinalRecognition(")
end = coordinator.index("\n    private func ", start + 10)
final_block = coordinator[start:end]
assert "reRecognizeWholeRecordingAfterStop: task.reRecognizeWholeRecordingAfterStop" in final_block, \
    "final recognition must use the task policy"
assert "controller.reRecognizeWholeRecordingAfterStopEnabled" not in final_block, \
    "final recognition must not reread mutable UI state"

print("RecordingFinalizationPolicyBoundaryCheck passed")
PY
