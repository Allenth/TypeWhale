#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COORDINATOR="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

grep -Fq 'systemDefaultConcreteDeviceID' "$COORDINATOR"
grep -Fq 'AudioInputDeviceProvider.currentDefaultInputDeviceID()' "$COORDINATOR"
grep -Fq 'system_default_coreaudio' "$COORDINATOR"
grep -Fq 'av_audio_engine_default' "$COORDINATOR"

echo "SystemDefaultMicrophoneCoreAudioCaptureCheck passed"
