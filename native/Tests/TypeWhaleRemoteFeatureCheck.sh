#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-remote-feature.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

/bin/zsh "$ROOT/native/Tests/run_remote_domain_checks.sh"
/bin/zsh "$ROOT/native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh"

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
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteHIDEventReducer.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/XiaomiRemote2ProHIDProfile.swift" \
  "$ROOT/native/Tests/RemoteHIDEventReducerCheck.swift" \
  -o "$OUT/RemoteHIDEventReducerCheck"
"$OUT/RemoteHIDEventReducerCheck"

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
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT/native/Sources/Application/RemoteActionExecutor.swift" \
  "$ROOT/native/Sources/Application/ClosureRemoteActionExecutors.swift" \
  "$ROOT/native/Sources/Application/RemoteButtonActionDispatcher.swift" \
  "$ROOT/native/Tests/RemoteButtonActionDispatcherCheck.swift" \
  -o "$OUT/RemoteButtonActionDispatcherCheck"
"$OUT/RemoteButtonActionDispatcherCheck"

xcrun swiftc \
  -framework ApplicationServices \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteKeyboardActionEmitter.swift" \
  "$ROOT/native/Tests/RemoteKeyboardActionEmitterCheck.swift" \
  -o "$OUT/RemoteKeyboardActionEmitterCheck"
"$OUT/RemoteKeyboardActionEmitterCheck"

xcrun swiftc \
  -framework ApplicationServices \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteKeyboardActionEmitter.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteSystemEventProfile.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteMappedEventSuppressionGate.swift" \
  "$ROOT/native/Tests/RemoteMappedEventSuppressionGateCheck.swift" \
  -o "$OUT/RemoteMappedEventSuppressionGateCheck"
"$OUT/RemoteMappedEventSuppressionGateCheck"

xcrun swiftc \
  -parse-as-library \
  -framework IOKit \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteHIDEventReducer.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/XiaomiRemote2ProHIDProfile.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemotePowerKeyNeutralizer.swift" \
  "$ROOT/native/Tests/RemotePowerKeyNeutralizerCheck.swift" \
  -o "$OUT/RemotePowerKeyNeutralizerCheck"
"$OUT/RemotePowerKeyNeutralizerCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteVoiceKeySuppressionGate.swift" \
  "$ROOT/native/Tests/RemoteVoiceKeySuppressionGateCheck.swift" \
  -o "$OUT/RemoteVoiceKeySuppressionGateCheck"
"$OUT/RemoteVoiceKeySuppressionGateCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Application/RemoteSpeechSessionPolicy.swift" \
  "$ROOT/native/Tests/RemoteSpeechSessionPolicyCheck.swift" \
  -o "$OUT/RemoteSpeechSessionPolicyCheck"
"$OUT/RemoteSpeechSessionPolicyCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteVoiceControlPolicy.swift" \
  "$ROOT/native/Tests/RemoteVoiceControlPolicyCheck.swift" \
  -o "$OUT/RemoteVoiceControlPolicyCheck"
"$OUT/RemoteVoiceControlPolicyCheck"

xcrun swiftc \
  -parse-as-library \
  "$ROOT/native/Sources/Domain/Remote/RemoteAudioInputCompatibilityPolicy.swift" \
  "$ROOT/native/Tests/RemoteAudioInputCompatibilityPolicyCheck.swift" \
  -o "$OUT/RemoteAudioInputCompatibilityPolicyCheck"
"$OUT/RemoteAudioInputCompatibilityPolicyCheck"

xcrun swiftc \
  -framework AVFAudio \
  "$ROOT/native/Sources/Infrastructure/Audio/RemotePCMBufferFactory.swift" \
  "$ROOT/native/Tests/AudioRecorderExternalPCMCheck.swift" \
  -o "$OUT/AudioRecorderExternalPCMCheck"
"$OUT/AudioRecorderExternalPCMCheck"

for check in \
  AudioRecorderExternalPCMBoundaryCheck.sh \
  AudioRecorderFanOutSourceCheck.sh \
  AudioRecorderFinalizationBoundaryCheck.sh \
  ManualAudioInputCaptureBoundaryCheck.sh \
  RemoteBluetoothBoundaryCheck.sh \
  TypeWhaleRemoteHIDIsolationFeatureCheck.sh \
  RemoteAudioSourceCoexistenceBoundaryCheck.sh \
  RemoteSpeechCoordinatorBoundaryCheck.sh \
  RemoteTabBoundaryCheck.sh
do
  /bin/zsh "$ROOT/native/Tests/$check"
done

UI_SPEC_VALIDATOR="${TYPEWHALE_UI_SPEC_VALIDATOR:-}"
if [[ -n "$UI_SPEC_VALIDATOR" && -f "$UI_SPEC_VALIDATOR" ]]; then
  /usr/bin/python3 \
    "$UI_SPEC_VALIDATOR" \
    "$ROOT/docs/design/xiaomi-remote-tab/spec.json" \
    --final
else
  /usr/bin/python3 -m json.tool \
    "$ROOT/docs/design/xiaomi-remote-tab/spec.json" \
    >/dev/null
fi

grep -Fq -- '-framework CoreBluetooth' "$ROOT/native/build_native_app.sh"
grep -Fq -- '-framework IOKit' "$ROOT/native/build_native_app.sh"
grep -Fq 'NSBluetoothAlwaysUsageDescription' "$ROOT/native/build_native_app.sh"
grep -Fq 'HD838A/remote-mic-app' "$ROOT/THIRD_PARTY_NOTICES.md"
grep -Fq 'fanxeon/mi-ao' "$ROOT/THIRD_PARTY_NOTICES.md"
grep -Fq 'CoreBluetooth ATVV' "$ROOT/docs/current/ARCHITECTURE.md"

print "TypeWhaleRemoteFeatureCheck passed"
