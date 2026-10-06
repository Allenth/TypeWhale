#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

sleep_cancel_block="$(
  awk '
    /private func cancelRecordingForSystemSleep\(reason: String\)/ { in_block=1 }
    in_block { print }
    in_block && /^    private func / && !/cancelRecordingForSystemSleep/ { exit }
  ' "$SOURCE"
)"

grep -Fq 'suppressNextHotkeyUp = hotkeyIsPressed' <<<"$sleep_cancel_block"
if grep -Fq 'suppressNextHotkeyUp = true' <<<"$sleep_cancel_block"; then
  echo "空闲睡眠不能无条件吞掉唤醒后的第一次 Fn" >&2
  exit 1
fi

capture_line="$(grep -Fn 'suppressNextHotkeyUp = hotkeyIsPressed' <<<"$sleep_cancel_block" | head -1 | cut -d: -f1)"
reset_line="$(grep -Fn 'hotkeyIsPressed = false' <<<"$sleep_cancel_block" | head -1 | cut -d: -f1)"
if (( capture_line >= reset_line )); then
  echo "必须先读取真实按键状态，再清除 hotkeyIsPressed" >&2
  exit 1
fi

echo "HotkeyWakeSuppressionBoundaryCheck passed"
