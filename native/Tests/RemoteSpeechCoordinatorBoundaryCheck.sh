#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATE="$ROOT/native/Sources/Application/SpeechInputState.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
REMOTE="$ROOT/native/Sources/Application/RemoteInputCoordinator.swift"

test -f "$REMOTE"
grep -Fq 'enum SpeechCaptureSource' "$STATE"
grep -Fq 'let captureSource: SpeechCaptureSource' "$STATE"
grep -Fq 'captureSource: SpeechCaptureSource = .microphone' "$COORDINATOR"
grep -Fq 'func beginRemoteSpeech(sampleRate:' "$COORDINATOR"
grep -Fq 'func appendRemotePCM16(' "$COORDINATOR"
grep -Fq 'func endRemoteSpeech(' "$COORDINATOR"
grep -Fq 'func cancelRemoteSpeech(' "$COORDINATOR"
grep -Fq 'try recorder.startExternal(' "$COORDINATOR"
grep -Fq 'session.captureSource.isRemote' "$COORDINATOR"
grep -Fq 'RemoteSpeechSessionPolicy' "$REMOTE"
grep -Fq 'remoteSessionPolicy.allowsPCM' "$REMOTE"

python3 - "$COORDINATOR" "$REMOTE" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
start = source.index("private func startRecording(")
permission = source.index("PermissionDiagnosticsProvider.microphoneAccessState()", start)
guard = source.rfind("captureSource.requiresMicrophonePermission", start, permission)
if guard < start:
    raise SystemExit("remote capture must bypass microphone permission before the permission switch")

remote = Path(sys.argv[2]).read_text()
start_body = remote[remote.index("    func start()") : remote.index("    func stop()")]
resume_body = remote[remote.index("    func resume()") : remote.index("    func setEnabled(")]
if "synchronizeHIDMonitoring()" not in start_body:
    raise SystemExit("startup must honor the saved remote enabled state before opening HID monitoring")
if "synchronizeHIDMonitoring()" not in resume_body:
    raise SystemExit("wake resume must honor the saved remote enabled state before opening HID monitoring")
if "private func synchronizeHIDMonitoring()" not in remote:
    raise SystemExit("remote HID lifecycle must have one enabled-state synchronization path")
sync_body = remote[remote.index("    private func synchronizeHIDMonitoring()") :]
if "if snapshot.enabled" not in sync_body or "hid.start()" not in sync_body or "hid.stop()" not in sync_body:
    raise SystemExit("disabled remote mode must keep RC003 HID monitoring and F5 suppression off")
if "bluetooth.observeVoiceButton(isDown: true)" not in remote or "bluetooth.observeVoiceButton(isDown: false)" not in remote:
    raise SystemExit("RC003 voice HID down/up must reach Bluetooth control so AUDIO_START-only firmware can be correlated safely")
if ".startsRemoteSpeech" not in remote or "actionCycleTracker" not in remote:
    raise SystemExit("RC003 voice audio eligibility must follow the action captured for the full physical press cycle")
PY

print "RemoteSpeechCoordinatorBoundaryCheck passed"
