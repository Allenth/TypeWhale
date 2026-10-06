#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-remote-r0.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Tests/RemoteActionCatalogCheck.swift" \
  -o "$OUT/RemoteActionCatalogCheck"
"$OUT/RemoteActionCatalogCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT/native/Tests/RemoteMappingMigrationCheck.swift" \
  -o "$OUT/RemoteMappingMigrationCheck"
"$OUT/RemoteMappingMigrationCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteInputSettingsStore.swift" \
  "$ROOT/native/Tests/RemoteInputSettingsStoreCheck.swift" \
  -o "$OUT/RemoteInputSettingsStoreCheck"
"$OUT/RemoteInputSettingsStoreCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Sources/Application/RemoteActionExecutor.swift" \
  "$ROOT/native/Sources/Application/ClosureRemoteActionExecutors.swift" \
  "$ROOT/native/Sources/Application/RemoteButtonActionDispatcher.swift" \
  "$ROOT/native/Tests/RemoteButtonActionDispatcherCheck.swift" \
  -o "$OUT/RemoteButtonActionDispatcherCheck"
"$OUT/RemoteButtonActionDispatcherCheck"

if rg -n 'UserDefaults|CGEvent|IOHID|NSWorkspace|AppKit' \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift"; then
  print -u2 "Remote action Domain must not own persistence, UI, HID or system APIs"
  exit 1
fi

if rg -n 'CGEvent|IOHID|NSWorkspace|UserDefaults' \
  "$ROOT/native/Sources/Application/RemoteButtonActionDispatcher.swift"; then
  print -u2 "Remote dispatcher must only route actions"
  exit 1
fi

print "TypeWhaleRemoteActionPlatformR0Check passed"
