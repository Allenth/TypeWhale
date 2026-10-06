#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PREFS="$ROOT/native/Sources/Presentation/Main/MainViewController+Preferences.swift"

SHORTCUT_ROW="$(awk '
    /func shortcutRow\(/ { in_row = 1 }
    in_row && /func optionRow\(/ { exit }
    in_row { print }
' "$PREFS")"

if ! grep -q 'captureButton.translatesAutoresizingMaskIntoConstraints = false' <<< "$SHORTCUT_ROW"; then
  echo "shortcutRow capture buttons must disable autoresizing-mask constraints so mouse hit-testing matches the visible button." >&2
  exit 1
fi

if ! grep -q 'fallbackButton.translatesAutoresizingMaskIntoConstraints = false' <<< "$SHORTCUT_ROW"; then
  echo "shortcutRow fallback buttons must disable autoresizing-mask constraints so rows do not overlap in hit-testing." >&2
  exit 1
fi

echo "HotkeyShortcutRowLayoutCheck passed"
