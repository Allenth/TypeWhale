#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REMOTE="$ROOT/native/Sources/Application/RemoteInputCoordinator.swift"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'var isEnabled: Bool' "$REMOTE"
grep -Fq 'RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault' "$SPEECH"
grep -Fq 'audio_input_selection_migrated reason=legacy_remote_virtual_device' "$SPEECH"

python3 - "$SPEECH" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
microphone = source.index("case .microphone:")
resolve = source.index("AudioInputDeviceProvider.resolveSelectedInput", microphone)
migrate = source.index("RemoteAudioInputCompatibilityPolicy.shouldMigrateToSystemDefault", resolve)
capture = source.index("let systemDefaultConcreteDeviceID", migrate)
if not resolve < migrate < capture:
    raise SystemExit("legacy virtual-input migration must happen before microphone capture starts")
PY

print "RemoteAudioSourceCoexistenceBoundaryCheck passed"
