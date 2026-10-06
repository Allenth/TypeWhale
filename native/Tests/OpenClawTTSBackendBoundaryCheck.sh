#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift"
PLAYER="$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"

test -f "$BACKEND"
grep -q 'protocol OpenClawTTSBackend: AnyObject' "$BACKEND"
grep -q 'var isRunning: Bool' "$BACKEND"
grep -q 'func start(timeoutSeconds: TimeInterval) throws' "$BACKEND"
grep -q 'func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval) throws' "$BACKEND"
grep -q 'func stop()' "$BACKEND"
grep -q 'final class ZipVoiceTTSBackend: OpenClawTTSBackend' "$PLAYER"
grep -q 'private var activeBackend: OpenClawTTSBackend?' "$PLAYER"
grep -q 'private var backendGeneration = 0' "$PLAYER"
grep -q 'private func ensureBackend(settings: OpenClawVoiceSettings) throws -> OpenClawTTSBackend' "$PLAYER"
grep -q 'backend.synthesize(request, timeoutSeconds: 180)' "$PLAYER"
grep -q 'activeBackendEngine == settings.engine' "$PLAYER"
grep -q 'activeBackendPackDirectory == probeRequest.packDirectory' "$PLAYER"
grep -q 'request.settings.voiceID' "$PLAYER"
grep -q 'response.voiceID != voiceID' "$PLAYER"
! grep -q 'MeloTTSVoiceBackend' "$PLAYER"
! grep -q 'SherpaNativeTTSBackend' "$PLAYER"
! rg -n 'OpenClawReplyPresenter|RecordingCapsule|RealtimePreview|SpeechInputCoordinator' "$BACKEND" "$PLAYER"

echo "OpenClawTTSBackendBoundaryCheck passed"
