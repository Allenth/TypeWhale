#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/typewhale-remote-domain-checks"
mkdir -p "$OUT"

xcrun swiftc \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteADPCMDecoder.swift" \
  "$ROOT/native/Tests/RemoteADPCMDecoderCheck.swift" \
  -o "$OUT/RemoteADPCMDecoderCheck"
"$OUT/RemoteADPCMDecoderCheck"

xcrun swiftc \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteADPCMDecoder.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteATVVProtocol.swift" \
  "$ROOT/native/Tests/RemoteATVVProtocolCheck.swift" \
  -o "$OUT/RemoteATVVProtocolCheck"
"$OUT/RemoteATVVProtocolCheck"

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
  "$ROOT/native/Sources/Domain/Remote/RemoteInputModels.swift" \
  "$ROOT/native/Tests/RemoteConnectionPolicyCheck.swift" \
  -o "$OUT/RemoteConnectionPolicyCheck"
"$OUT/RemoteConnectionPolicyCheck"

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
  "$ROOT/native/Tests/RemoteButtonMappingCheck.swift" \
  -o "$OUT/RemoteButtonMappingCheck"
"$OUT/RemoteButtonMappingCheck"

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
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonActionCycleTracker.swift" \
  "$ROOT/native/Tests/RemoteButtonActionCycleCheck.swift" \
  -o "$OUT/RemoteButtonActionCycleCheck"
"$OUT/RemoteButtonActionCycleCheck"

print "run_remote_domain_checks passed"
