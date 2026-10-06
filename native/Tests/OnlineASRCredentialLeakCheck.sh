#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/native/Sources/Infrastructure/Security/OnlineASRCredentialStore.swift"
SETTINGS="$ROOT/native/Sources/Infrastructure/Settings/OnlineASRSettings.swift"
MAIN="$ROOT/native/Sources/Presentation/Main"

grep -Fq 'com.waykingah.typewhale.pro.online-asr.doubao' "$SOURCE"
grep -Fq 'com.waykingah.typewhale.pro.online-asr.mimo-v2.5' "$SOURCE"
grep -Fq 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' "$SOURCE"

if grep -Fq 'UserDefaults' "$SOURCE" || grep -Eiq 'api.?key|credential' "$SETTINGS"; then
  echo "Online ASR credential must not enter UserDefaults" >&2
  exit 1
fi
if grep -Eiq 'LaunchDiagnostics.*(credential|api.?key)|Authorization: Bearer.*\\\(' "$SOURCE" "$SETTINGS"; then
  echo "Online ASR credential must not enter diagnostics" >&2
  exit 1
fi
if grep -R -Eq 'OnlineASRCredentialStore[^\n]*\.load|credentialStore\.load' "$MAIN" 2>/dev/null; then
  echo "Main UI must never load a credential value for display" >&2
  exit 1
fi

echo "OnlineASRCredentialLeakCheck passed"
