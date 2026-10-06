#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIPELINE="$ROOT/native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift"

grep -q 'previewTimeoutSeconds' "$PIPELINE"
grep -q 'timeoutWorkItemsByRequestID' "$PIPELINE"
grep -q 'scheduleTimeout(for: request' "$PIPELINE"
grep -q 'cancelTimeout(for: request.requestID)' "$PIPELINE"
grep -q 'preview_request_timeout lane=' "$PIPELINE"
grep -q 'scheduler.complete(' "$PIPELINE"
grep -q 'continueStopFinalizationIfReady()' "$PIPELINE"
