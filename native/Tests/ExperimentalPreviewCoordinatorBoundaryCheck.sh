#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATE="$ROOT/native/Sources/Application/SpeechInputState.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
PIPELINE="$ROOT/native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift"

grep -Fq 'let experimentalPreviewSettings: ExperimentalPreviewSettings' "$STATE"
grep -Fq 'private var experimentalPreviewPipeline' "$COORDINATOR"
grep -Fq 'recorder.onExperimentalPreviewSnapshot' "$COORDINATOR"
grep -Fq 'session.experimentalPreviewSettings.correctedPreviewEnabled' "$COORDINATOR"
grep -Fq 'experimentalPreviewEnabled: experimentalSettings.correctedPreviewEnabled' "$COORDINATOR"
grep -Fq 'receiveExperimentalCorrectionSnapshot' "$COORDINATOR"
grep -Fq 'applyExperimentalPreviewState' "$COORDINATOR"
grep -Fq 'sessionID + epoch + requestID' "$PIPELINE"
grep -Fq 'transcribeDetailed' "$PIPELINE"
grep -Fq 'startFinalRecognition(task' "$COORDINATOR"

echo "ExperimentalPreviewCoordinatorBoundaryCheck passed"
