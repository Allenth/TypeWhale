#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
CONTROLLER="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
LIFECYCLE="$ROOT/native/Sources/Application/AppLifecycleCoordinator.swift"

grep -q 'title: "完全退出"' "$PANEL"
grep -q 'systemSymbolName: "power"' "$PANEL"
grep -q '#selector(requestFullAppExit(_:))' "$PANEL"
grep -q 'var onRequestFullAppExit: (() -> Void)?' "$CONTROLLER"
grep -q '@objc func requestFullAppExit(_ sender: NSButton)' "$ACTIONS"
grep -q 'onRequestFullAppExit?()' "$ACTIONS"
grep -q 'controller.onRequestFullAppExit' "$LIFECYCLE"
grep -q 'func requestFullTermination()' "$LIFECYCLE"
grep -q 'requestFullTermination()' "$LIFECYCLE"
grep -q 'NSApp.terminate(nil)' "$LIFECYCLE"

echo "MainWindowFullExitCheck passed"
