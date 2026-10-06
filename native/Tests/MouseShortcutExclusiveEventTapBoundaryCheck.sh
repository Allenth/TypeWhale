#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
hotkey_monitor="$repo_root/native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift"
mouse_tap_block="$(sed -n '/private func startMouseEventTap/,/func handleFlagsChanged/p' "$hotkey_monitor")"

if grep -Fq 'options: .listenOnly' <<<"$mouse_tap_block"; then
    echo "Mouse shortcut event tap must be able to consume matched shortcuts; listenOnly always passes them through." >&2
    exit 1
fi

grep -Fq 'options: .defaultTap' <<<"$mouse_tap_block"

down_handler="$(sed -n '/type == .leftMouseDown/,/type == .leftMouseUp/p' <<<"$mouse_tap_block")"
up_handler="$(sed -n '/type == .leftMouseUp/,/return Unmanaged.passUnretained(event)/p' <<<"$mouse_tap_block")"

grep -Fq 'monitor.handleMouse(event: event, isDown: true)' <<<"$down_handler"
grep -Fq 'return nil' <<<"$down_handler"
grep -Fq 'monitor.handleMouse(event: event, isDown: false)' <<<"$up_handler"
grep -Fq 'return nil' <<<"$up_handler"
grep -Fq 'return Unmanaged.passUnretained(event)' <<<"$mouse_tap_block"

echo "MouseShortcutExclusiveEventTapBoundaryCheck passed"
