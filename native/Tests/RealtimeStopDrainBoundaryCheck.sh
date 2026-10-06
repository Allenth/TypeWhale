#!/usr/bin/env bash
set -euo pipefail

COORDINATOR="native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'drainRealtimePreviewForFinalDelivery' "$COORDINATOR"
grep -Fq 'realtime_stop_drain_timeout' "$COORDINATOR"
grep -Fq 'realtime_stop_drain_completed' "$COORDINATOR"

python3 - <<'PY'
from pathlib import Path

source = Path("native/Sources/Application/SpeechInputCoordinator.swift").read_text()
finish_start = source.index("    private func finishRecording(")
finish_end = source.index("\n    private func startFinalRecognition", finish_start)
finish = source[finish_start:finish_end]

drain = finish.index("await self.drainRealtimePreviewForFinalDelivery")
prepare = finish.index("self.prepareShadowPreviewForFinalDelivery")
discard = finish.index("self.discardPendingRealtimeSnapshot")
if not (drain < prepare < discard):
    raise SystemExit("stop-time realtime drain must happen before completing delivery cache and before discarding pending snapshots")

drain_start = source.index("    private func drainRealtimePreviewForFinalDelivery")
drain_end = source.index("\n    private func discardPendingRealtimeSnapshot", drain_start)
drain_body = source[drain_start:drain_end]
for state in ["realtimeBusy", "pendingRealtimeSnapshot", "pendingFinalSnapshots"]:
    if state not in drain_body:
        raise SystemExit(f"drain must observe {state}")
if ".asyncAfter" in drain_body:
    raise SystemExit("drain must be state-driven, not a fixed asyncAfter delay")

print("RealtimeStopDrainBoundaryCheck passed")
PY
