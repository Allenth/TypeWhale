#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOTKEY="$ROOT/native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
CLASSIC="$ROOT/native/Sources/Presentation/Capsule/RecordingPanel.swift"
NOTCH="$ROOT/native/Sources/Presentation/Notch/NotchPreviewPresenter.swift"
MINIMAL_BLACK="$ROOT/native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift"

grep -Fq 'hotkey_event phase=down' "$HOTKEY"
grep -Fq 'hotkey_event phase=up' "$HOTKEY"
grep -Fq 'hotkey_handler phase=down' "$COORDINATOR"
grep -Fq 'hotkey_handler phase=up' "$COORDINATOR"
grep -Fq 'capsule_show_requested' "$COORDINATOR"
grep -Fq 'capsule_show_result theme=classic' "$CLASSIC"
grep -Fq 'capsule_show_result theme=notch' "$NOTCH"
grep -Fq 'capsule_show_result theme=minimalBlack' "$MINIMAL_BLACK"

echo "HotkeyCapsuleVisibilityDiagnosticsBoundaryCheck passed"
