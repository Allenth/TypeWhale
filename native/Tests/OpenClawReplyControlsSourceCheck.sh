#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PRESENTER="$ROOT/native/Sources/Presentation/OpenClaw/OpenClawReplyPresenter.swift"

grep -q 'collapsesToOrbAfterIdle = true' "$PRESENTER"
grep -q 'idleTimeoutAction: Action = .collapseToOrb' "$PRESENTER"
grep -q 'clearButtonAction: Action = .clearMessages' "$PRESENTER"
grep -q 'orbClickAction: Action = .expandMessages' "$PRESENTER"
grep -q 'openclaw-reply-orb-button' "$PRESENTER"
grep -q 'collapseToOrb' "$PRESENTER"
grep -q 'expandFromOrb' "$PRESENTER"
grep -q 'OpenClawVoicePlayer.shared.stop()' "$PRESENTER"
grep -q 'OpenClawVoiceSettingsStore.standard.save' "$PRESENTER"
grep -q 'openclaw-reply-stop-voice-button' "$PRESENTER"
grep -q 'openclaw-reply-voice-toggle-button' "$PRESENTER"
grep -q 'openclaw-reply-collapse-button' "$PRESENTER"
grep -q 'collapseFromButton' "$PRESENTER"
