#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BLE="$ROOT/native/Sources/Infrastructure/Remote/RemoteBluetoothController.swift"
HID="$ROOT/native/Sources/Infrastructure/Remote/RemoteHIDMonitor.swift"
PROFILE="$ROOT/native/Sources/Infrastructure/Remote/XiaomiRemote2ProHIDProfile.swift"

test -f "$BLE"
test -f "$HID"
test -f "$PROFILE"
grep -Fq 'import CoreBluetooth' "$BLE"
grep -Fq 'retrieveConnectedPeripherals(withServices:' "$BLE"
grep -Fq 'scanForPeripherals(' "$BLE"
grep -Fq 'setNotifyValue(true, for:' "$BLE"
grep -Fq 'maximumCapabilityAttempts = 3' "$BLE"
grep -Fq 'RemoteATVVProtocol.getCapabilitiesCommand' "$BLE" || grep -Fq 'protocolHandler.getCapabilitiesCommand' "$BLE"
grep -Fq 'import IOKit.hid' "$HID"
grep -Fq 'kIOHIDVendorIDKey' "$HID"
grep -Fq 'XiaomiRemote2ProHIDProfile.vendorID' "$HID"
grep -Fq 'XiaomiRemote2ProHIDProfile.productID' "$HID"
grep -Fq '0x2717' "$PROFILE"
grep -Fq '0x32B8' "$PROFILE"
grep -Fq 'usage: 0x65' "$PROFILE"
grep -Fq 'IOHIDManagerRegisterInputValueCallback' "$HID"

if grep -Eq 'LaunchDiagnostics.*(identifier|uuidString|raw_packet|raw_data)' "$BLE"; then
  print -u2 "Bluetooth diagnostics must not persist device identifiers or raw packets"
  exit 1
fi

print "RemoteBluetoothBoundaryCheck passed"
