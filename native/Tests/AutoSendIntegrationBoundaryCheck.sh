#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

coordinator=native/Sources/Application/SpeechInputCoordinator.swift
state=native/Sources/Application/SpeechInputState.swift

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! rg -q "$pattern" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_pattern 'AutoSendPolicy' "$coordinator" "SpeechInputCoordinator must resolve AutoSendPolicy"
require_pattern 'postPasteAction:' "$coordinator" "paste enqueue must carry the resolved post action"
require_pattern 'wasTranslationRequested: true' "$coordinator" "translation path must freeze requested=true"
require_pattern 'wasTranslationRequested: false' "$coordinator" "ordinary path must freeze requested=false"
require_pattern 'result\.wasTranslationRequested' "$coordinator" "policy must read the frozen translation fact"
require_pattern 'result\.task\.purpose' "$coordinator" "policy must receive the frozen task purpose"
require_pattern 'RecentTargetApplicationStore\.record' "$coordinator" "successful paste must record the target app"
require_pattern 'let wasTranslationRequested: Bool' "$state" "PendingPasteResult must store translation-request state"
require_pattern \
  'schedulePostPasteActionIfNeeded' \
  native/Sources/Infrastructure/Paste/PasteCoordinator.swift \
  "default-none requests must bypass delayed post-action scheduling"

if rg -n 'PostPasteKeyEmitter' native/Sources/Presentation; then
  echo "Presentation must not emit post-paste system keys" >&2
  exit 1
fi

while IFS= read -r file; do
  case "$file" in
    native/Sources/Presentation/Main/MainViewController+Actions.swift|\
    native/Sources/Presentation/Main/MainViewController+Configuration.swift)
      ;;
    *)
      echo "Only the main settings controller may read auto-send settings: $file" >&2
      exit 1
      ;;
  esac
done < <(rg -l 'AutoSendSettingsStore' native/Sources/Presentation || true)

if rg -n 'AutoSendSettingsStore|UserDefaults' \
  native/Sources/Infrastructure/Paste/PasteCoordinator.swift; then
  echo "PasteCoordinator must not own auto-send policy/settings" >&2
  exit 1
fi

echo "AutoSendIntegrationBoundaryCheck passed"
