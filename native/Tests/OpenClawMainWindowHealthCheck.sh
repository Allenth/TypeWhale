#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIFECYCLE="$ROOT/native/Sources/Application/AppLifecycleCoordinator.swift"
APP="$ROOT/native/TypeSpeakerApp.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"

if ! grep -q "onMainWindowShown" "$LIFECYCLE"; then
  echo "AppLifecycleCoordinator must expose a main-window-only callback for work that should run when the main panel opens." >&2
  exit 1
fi

show_block="$(
  awk '
    /func showMainWindow\(\)/ { in_block=1 }
    in_block { print }
    in_block && /func suppressNextReopen/ { exit }
  ' "$LIFECYCLE"
)"
if ! grep -q "onMainWindowShown?()" <<<"$show_block"; then
  echo "Opening or reopening the main window must trigger the main-window callback." >&2
  exit 1
fi

menu_block="$(
  awk '
    /func menuWillOpen/ { in_block=1 }
    in_block { print }
    in_block && /private func updateMemoryStatusItem/ { exit }
  ' "$LIFECYCLE"
)"
if grep -q "onMainWindowShown" <<<"$menu_block"; then
  echo "Opening the status-bar menu must not trigger the OpenClaw main-window health check." >&2
  exit 1
fi

if ! grep -q "lifecycle.onMainWindowShown" "$APP" ||
   ! grep -q "refreshOpenClawConnectionOnMainWindowOpen" "$APP"; then
  echo "AppDelegate must wire main-window opens to an automatic OpenClaw health refresh." >&2
  exit 1
fi

if ! grep -q "func refreshOpenClawConnectionOnMainWindowOpen" "$ACTIONS" ||
   ! grep -q '"main_window_open"' "$ACTIONS" ||
   ! grep -q "runOpenClawConnectionCheck" "$ACTIONS"; then
  echo "MainViewController must provide a main-window OpenClaw health refresh that reuses the normal connection check path." >&2
  exit 1
fi

echo "OpenClawMainWindowHealthCheck passed"
