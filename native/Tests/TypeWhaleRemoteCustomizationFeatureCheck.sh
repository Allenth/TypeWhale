#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

/bin/zsh "$ROOT/native/Tests/TypeWhaleAutoSendCancellationFeatureCheck.sh"
/bin/zsh "$ROOT/native/Tests/TypeWhaleRemoteFeatureCheck.sh"

grep -Fq 'RemoteActionCatalog.builtIn.allowedActions(for:' \
  "$ROOT/native/Sources/Presentation/Remote/RemoteButtonActionPresentation.swift"
grep -Fq '.descriptor(for: RemoteActionID(rawValue: rawValue))' \
  "$ROOT/native/Sources/Presentation/Remote/RemoteButtonMappingView.swift"
grep -Fq 'actionDispatcher.dispatch(binding, for: button)' \
  "$ROOT/native/Sources/Application/RemoteInputCoordinator.swift"
grep -Fq '自定义动作会替换该键的系统原动作' \
  "$ROOT/native/Sources/Presentation/Remote/RemoteButtonMappingView.swift"
grep -Fq 'RemoteMappedEventSuppressionRegistry.shared.observeRemoteHID' \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteHIDMonitor.swift"
grep -Fq 'RemoteMappedEventSuppressionRegistry.shared.decide' \
  "$ROOT/native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift"
grep -Fq 'powerKeyNeutralizer.isNeutralized' \
  "$ROOT/native/Sources/Application/RemoteInputCoordinator.swift"
grep -Fq 'pressedButton: snapshot.pressedButton' \
  "$ROOT/native/Sources/Presentation/Remote/RemoteInspectorView.swift"
grep -Fq 'mappingView.onButtonPreview' \
  "$ROOT/native/Sources/Presentation/Remote/RemoteInspectorView.swift"

print "TypeWhaleRemoteCustomizationFeatureCheck passed"
