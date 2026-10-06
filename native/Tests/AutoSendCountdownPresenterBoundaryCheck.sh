#!/usr/bin/env bash
set -euo pipefail

file=native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift

rg -q 'nonactivatingPanel' "$file"
rg -q 'ignoresMouseEvents = false' "$file"
rg -q 'override var canBecomeKey: Bool \{ false \}' "$file"
rg -q 'capsuleFrame: @escaping \(\) -> CGRect\?' "$file"
rg -q 'AutoSendCountdownLayout\.origin' "$file"
rg -q '2\.0 秒后发送' "$file"
rg -q 'AutoSendCountdownClickView' "$file"
rg -q 'override func mouseDown' "$file"
rg -q 'onClick\?\(\)' "$file"
rg -q 'countdownLabel\.alignment = \.center' "$file"
rg -q 'countdownLabel\.centerXAnchor\.constraint' "$file"
if rg -n 'NSButton|cancelButton|divider' "$file"; then
  echo "Countdown strip must not render a separate cancel button or divider" >&2
  exit 1
fi
if rg -n 'PostPasteKeyEmitter|AutoSendSettingsStore|UserDefaults|Timer\(' "$file"; then
  echo "Presenter must only render snapshots and forward cancel intent" >&2
  exit 1
fi

echo "AutoSendCountdownPresenterBoundaryCheck passed"
