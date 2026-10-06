#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

if [[ ! -f "$SOURCE" ]]; then
  echo "Missing SpeechInputCoordinator.swift" >&2
  exit 1
fi

health_block="$(
  awk '
    /private func performBackgroundHealthCheck\(\)/ { in_block=1 }
    in_block { print }
    in_block && /^    private func / && !/performBackgroundHealthCheck/ { exit }
  ' "$SOURCE"
)"

if ! grep -Fq "hotkey.isGlobalListening" <<<"$health_block"; then
  echo "performBackgroundHealthCheck must verify global hotkey listening state" >&2
  exit 1
fi

if ! grep -Fq 'startHotkey(reason: "background_health_hotkey_recovery")' <<<"$health_block"; then
  echo "performBackgroundHealthCheck must restart the hotkey tap during idle health checks" >&2
  exit 1
fi

if ! grep -Fq "PermissionDiagnosticsProvider.current().accessibilityTrusted" <<<"$health_block"; then
  echo "hotkey recovery must respect Accessibility permission state" >&2
  exit 1
fi

echo "HotkeyIdleRecoveryBoundaryCheck passed"
