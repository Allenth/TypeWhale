#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PRESENTER="$ROOT/native/Sources/Presentation/OpenClaw/OpenClawReplyPresenter.swift"

grep -q 'OpenClawReplyCopyButton' "$PRESENTER"
grep -q 'OpenClawReplyCopyableBubbleView' "$PRESENTER"
grep -q 'copyMessage' "$PRESENTER"
grep -q 'NSPasteboard.general' "$PRESENTER"
grep -q 'ToastPresenter.shared.show("复制成功"' "$PRESENTER"
python3 - "$PRESENTER" <<'PY'
import sys
source = open(sys.argv[1], encoding="utf-8").read()
for identifier in ["openclaw-reply-user-bubble", "openclaw-reply-status-bubble"]:
    start = source.index(f'accessibilityIdentifier: "{identifier}"')
    snippet = source[start:start + 260]
    assert "copyText: text" in snippet, f"{identifier} is not double-click copyable"
PY
grep -q 'OpenClawVoicePlaybackNotification.didStartSpeaking' "$PRESENTER"
grep -q 'isSpeaking: isOpenClawSpeaking' "$PRESENTER"
grep -q 'pulseLayer' "$PRESENTER"
grep -q 'waveformLayer' "$PRESENTER"
